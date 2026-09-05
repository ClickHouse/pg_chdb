-- https://github.com/ClickHouse/ClickHouse/issues/29693#issuecomment-4755761107
BEGIN;
SET client_min_messages TO WARNING;

-- Table name `target` required by util.pgsql/load_target().
CREATE TABLE target (
    updated_at  TIMESTAMPTZ,
    id          BIGINT,
    deleted     SMALLINT,
    type        post_type,
    author      TEXT,
    created_at  TIMESTAMPTZ,
    body        TEXT,
    dead        BOOLEAN,
    parent      BIGINT,
    poll        BIGINT,
    children    BIGINT[],
    url         TEXT,
    score       BIGINT,
    title       TEXT,
    parts       BIGINT[],
    descendants BIGINT
);

\ir util.pgsql

COPY(SELECT * FROM load_target('hackernews', 'TabSeparatedWithNames', 'none', 'hackernews/hackernews.tsv')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'TabSeparatedWithNames', 'gzip', 'hackernews/hackernews.tsv.gz')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'CSVWithNames', 'none', 'hackernews/hackernews.csv')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'CSVWithNames', 'gzip', 'hackernews/hackernews.csv.gz')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'JSONEachRow', 'none', 'hackernews/hackernews.json')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'JSONEachRow', 'gzip', 'hackernews/hackernews.json.gz')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'Parquet', 'zstd', 'hackernews/hackernews.parquet')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'Arrow', 'lz4', 'hackernews/hackernews.arrow')) TO STDOUT;
COPY(SELECT * FROM load_target('hackernews', 'Avro', 'snappy', 'hackernews/hackernews.avro')) TO STDOUT;

ROLLBACK;
