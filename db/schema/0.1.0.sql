CREATE SCHEMA en57;

CREATE TABLE en57.events (
    position bigint GENERATED ALWAYS AS IDENTITY,
    id uuid PRIMARY KEY,
    type text NOT NULL,
    data jsonb,
    meta jsonb
);

CREATE TABLE en57.tags (
    event_id uuid NOT NULL REFERENCES en57.events (id) ON DELETE CASCADE,
    value text NOT NULL,
    PRIMARY KEY (event_id, value)
);

CREATE INDEX events_type_idx ON en57.events (type);

CREATE INDEX tags_value_event_id_idx ON en57.tags (value, event_id);

CREATE TYPE en57.event AS (
    id uuid,
    type text,
    data jsonb,
    meta jsonb,
    tags text[]
);

CREATE FUNCTION en57.append_events (new_events en57.event[], append_condition jsonb DEFAULT '{}'::jsonb)
    RETURNS void
    LANGUAGE plpgsql
    SET enable_seqscan = OFF
    AS $$
DECLARE
    criteria jsonb[] := ARRAY (
        SELECT
            jsonb_array_elements(COALESCE(append_condition -> 'fail_if_events_match', '[]'::jsonb)));
    criterion jsonb;
    req_types text[];
    req_tags text[];
    req_after bigint;
BEGIN
    FOREACH criterion IN ARRAY criteria LOOP
        req_after := (criterion ->> 'after')::bigint;
        req_types := ARRAY (
            SELECT
                jsonb_array_elements_text(COALESCE(criterion -> 'types', '[]'::jsonb)));
        req_tags := ARRAY ( SELECT DISTINCT
                jsonb_array_elements_text(COALESCE(criterion -> 'tags', '[]'::jsonb)));
        IF cardinality(req_tags) > 0 THEN
            IF EXISTS (
                SELECT
                    1
                FROM (
                    SELECT
                        t.event_id
                    FROM
                        en57.tags AS t
                    WHERE
                        t.value = ANY (req_tags)
                    GROUP BY
                        t.event_id
                    HAVING
                        count(*) = cardinality(req_tags)) AS matched
                    JOIN en57.events AS e ON e.id = matched.event_id
                WHERE (req_after IS NULL
                    OR e.position > req_after)
                AND (criterion -> 'types' IS NULL
                    OR e.type = ANY (req_types))) THEN
        RAISE EXCEPTION 'append_condition_violated';
        END IF;
    ELSE
        IF EXISTS (
            SELECT
                1
            FROM
                en57.events AS e
            WHERE (req_after IS NULL
                OR e.position > req_after)
            AND (criterion -> 'types' IS NULL
                OR e.type = ANY (req_types))) THEN
    RAISE EXCEPTION 'append_condition_violated';
    END IF;
END IF;
END LOOP;
INSERT INTO en57.events (id, type, data, meta)
SELECT
    e.id,
    e.type,
    e.data,
    e.meta
FROM
    unnest(new_events) AS e;
INSERT INTO en57.tags (event_id, value)
SELECT
    e.id,
    t.value
FROM
    unnest(new_events) AS e
    CROSS JOIN LATERAL unnest(COALESCE(e.tags, ARRAY[]::text[])) AS t (value);
END;
$$;

CREATE FUNCTION en57.read_events (criteria jsonb[])
    RETURNS TABLE (
        "position" bigint,
        id uuid,
        type text,
        data jsonb,
        meta jsonb,
        tags text[])
    LANGUAGE SQL
    AS $$
    WITH parsed_criteria AS (
        SELECT
            c,
            c -> 'tags' AS tags,
            (c ->> 'after')::bigint AS after,
            ARRAY (
                SELECT
                    jsonb_array_elements_text(c -> 'types')) AS types
        FROM
            unnest(criteria) AS c
),
filtered_events AS (
    SELECT
        e.position,
        e.id,
        e.type,
        e.data,
        e.meta
    FROM
        en57.events AS e
    WHERE
        cardinality(criteria) = 0
        OR EXISTS (
            SELECT
                1
            FROM
                parsed_criteria AS pc
            WHERE (pc.after IS NULL
                OR e.position > pc.after)
            AND (pc.c -> 'types' IS NULL
                OR e.type = ANY (pc.types))
            AND NOT EXISTS (
                SELECT
                    1
                FROM
                    jsonb_array_elements_text(COALESCE(pc.tags, '[]'::jsonb)) AS req (value)
                WHERE
                    NOT EXISTS (
                        SELECT
                            1
                        FROM
                            en57.tags AS t
                        WHERE
                            t.event_id = e.id
                            AND t.value = req.value))))
    SELECT
        e.position,
        e.id,
        e.type,
        e.data,
        e.meta,
        COALESCE(t.tags, ARRAY[]::text[]) AS tags
FROM
    filtered_events AS e
    LEFT JOIN LATERAL (
        SELECT
            array_agg(t.value ORDER BY t.value) AS tags
        FROM
            en57.tags AS t
        WHERE
            t.event_id = e.id) AS t ON TRUE
ORDER BY
    e.position;
$$;

