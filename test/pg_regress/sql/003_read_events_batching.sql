TRUNCATE TABLE en57.tags, en57.events RESTART IDENTITY CASCADE;

INSERT INTO en57.events (id, type, data, meta)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'OrderPlaced', '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000002', 'OrderPlaced', '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000003', 'OrderPlaced', '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000004', 'OrderPlaced', '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000005', 'OrderPlaced', '{}'::jsonb, '{}'::jsonb);

-- batch_size caps the number of rows returned (first keyset page)
SELECT
    position,
    id::text
FROM
    en57.read_events (ARRAY[]::jsonb[], 2)
ORDER BY
    position;

-- after_position is a keyset cursor; combined with batch_size it yields the next page
SELECT
    position,
    id::text
FROM
    en57.read_events (ARRAY[]::jsonb[], 2, 2)
ORDER BY
    position;

-- a cursor at or past the last position returns no further rows
SELECT
    position,
    id::text
FROM
    en57.read_events (ARRAY[]::jsonb[], 2, 5)
ORDER BY
    position;
