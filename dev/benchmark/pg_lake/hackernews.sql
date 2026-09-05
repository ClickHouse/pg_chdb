-- https://github.com/ClickHouse/ClickHouse/issues/29693#issuecomment-4755761107
BEGIN;
SET client_min_messages TO WARNING;

-- Table name `target` required by util.pgsql/load_target().
CREATE TABLE target (
    id          BIGINT,
    deleted     SMALLINT,
    type        TEXT,
    author      TEXT,
    timestamp   TIMESTAMPTZ,
    comment     TEXT,
    dead        SMALLINT,
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

COPY (SELECT * FROM load_target('hackernews', 'CSV', 'none', 'hackernews/hackernews.csv')) TO STDOUT;
COPY (SELECT * FROM load_target('hackernews', 'CSV', 'gzip', 'hackernews/hackernews.csv.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('hackernews', 'JSON', 'none', 'hackernews/hackernews.json')) TO STDOUT;
COPY (SELECT * FROM load_target('hackernews', 'JSON', 'gzip', 'hackernews/hackernews.json.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('hackernews', 'Parquet', 'zstd', 'hackernews/hackernews.parquet')) TO STDOUT;

ROLLBACK;
