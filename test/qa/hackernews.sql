-- https://clickhouse.com/docs/get-started/sample-datasets/hacker-news

DROP TABLE IF EXISTS hackernews;
CREATE TABLE hackernews (
    id          BIGINT      NOT NULL,
    deleted     SMALLINT    NOT NULL,
    type        TEXT        NOT NULL,
    author      TEXT        NOT NULL,
    timestamp   TIMESTAMPTZ NOT NULL,
    comment     TEXT        NOT NULL,
    dead        SMALLINT    NOT NULL,
    parent      BIGINT      NOT NULL,
    poll        BIGINT      NOT NULL,
    children    BIGINT[]    NOT NULL,
    url         TEXT        NOT NULL,
    score       BIGINT      NOT NULL,
    title       TEXT        NOT NULL,
    parts       BIGINT[]    NOT NULL,
    descendants BIGINT      NOT NULL
);

LOAD 'chdb_hook';
\timing on
COPY hackernews FROM 's3://datasets-documentation/hackernews/hacknernews.parquet';
