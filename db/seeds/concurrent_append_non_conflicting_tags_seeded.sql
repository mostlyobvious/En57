-- Seeds 1,000,000 events, each carrying a single random "writer:<8 hex>" tag.
-- The tag shape mirrors ConcurrentAppendNonConflictingTagsSeeded's
-- `writer:#{SecureRandom.hex(4)}`, so the tag index is populated with values
-- of the same shape the benchmark queries.
INSERT INTO en57.events (id, type)
SELECT
    gen_random_uuid(),
    'event_benchmarked'
FROM
    generate_series(1, 1000000);

INSERT INTO en57.tags (event_id, value)
SELECT
    id,
    'writer:' || substr(md5(random()::text), 1, 8)
FROM
    en57.events;
