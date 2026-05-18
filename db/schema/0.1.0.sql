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
    RETURNS TABLE ("position" bigint, conflicting_events text)
    LANGUAGE plpgsql
    AS $$
#variable_conflict use_column
DECLARE
    criteria jsonb[] := ARRAY (
        SELECT
            jsonb_array_elements(COALESCE(append_condition -> 'fail_if_events_match', '[]'::jsonb)));
    conflicts jsonb;
    conflict_max_position bigint;
    last_position bigint;
BEGIN
    IF cardinality(criteria) > 0 THEN
        WITH matches AS (
            SELECT
                e.position,
                jsonb_build_object('id', e.id, 'type', e.type, 'data', e.data::text, 'meta', e.meta::text, 'tags', COALESCE((
                    SELECT
                        array_agg(t.value ORDER BY t.value) FROM en57.tags AS t
                    WHERE
                        t.event_id = e.id), ARRAY[]::text[])) AS event_obj
            FROM
                en57.events AS e
            WHERE
                EXISTS (
                    SELECT
                        1
                    FROM
                        unnest(criteria) AS c
                    WHERE ((c ->> 'after')::bigint IS NULL OR e.position > (c ->> 'after')::bigint) AND (c -> 'types' IS NULL OR e.type IN (
SELECT
    jsonb_array_elements_text(c -> 'types'))) AND NOT EXISTS (
SELECT
    1
FROM
    jsonb_array_elements_text(COALESCE(c -> 'tags', '[]'::jsonb)) AS req (value)
WHERE
    NOT EXISTS (
    SELECT
        1
    FROM
        en57.tags AS t
    WHERE
        t.event_id = e.id AND t.value = req.value)))
)
        SELECT
            max(position),
            jsonb_agg(event_obj ORDER BY position) INTO conflict_max_position,
            conflicts
        FROM
            matches;
        IF conflict_max_position IS NOT NULL THEN
            RETURN QUERY SELECT conflict_max_position, conflicts::text;
            RETURN;
        END IF;
    END IF;
    WITH inserted AS (
        INSERT INTO en57.events (id, type, data, meta)
        SELECT
            e.id,
            e.type,
            e.data,
            e.meta
        FROM
            unnest(new_events) AS e
        RETURNING position
    )
    SELECT max(position) INTO last_position FROM inserted;
    INSERT INTO en57.tags (event_id, value)
    SELECT
        e.id,
        t.value
    FROM
        unnest(new_events) AS e
    CROSS JOIN LATERAL unnest(COALESCE(e.tags, ARRAY[]::text[])) AS t (value);
    RETURN QUERY SELECT last_position, '[]'::text;
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

