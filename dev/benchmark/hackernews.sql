SET client_min_messages TO WARNING;
SET datestyle TO ISO;
SET timezone TO UTC;
\getenv workdir WORKDIR
\set file_base file:// :workdir

LOAD 'chdb_hook';

-- https://github.com/ClickHouse/ClickHouse/issues/29693#issuecomment-4755761107

SELECT NOT EXISTS(select 1 from pg_type where typname = 'post_type') AS no_post_type \gset
\if :no_post_type
    CREATE TYPE post_type AS ENUM('story', 'comment', 'poll', 'pollopt', 'job');
\endif

CREATE TABLE IF NOT EXISTS hackernews (
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

-- Insert the records if they're not present.
SELECT NOT EXISTS (SELECT 1 FROM hackernews LIMIT 1) AS is_empty \gset
\if :is_empty
    \echo Loading ch-hackernews.csv.gz
    \set orig_file :file_base /ch-hackernews.csv.gz
    COPY hackernews FROM :'orig_file' (format 'CSV');
\endif

\set structure 'update_time DateTime64, id UInt32, deleted Bool, type Enum8(''story''=1,''comment''=2,''poll''=3,''pollopt''=4,''job''=5), by LowCardinality(String), time DateTime64, text String, dead Bool, parent UInt32, poll UInt32, kids Array(UInt32), url String, score Int32, title String, parts Array(UInt32), descendants Int32'

\if `[ ! -f hackernews.tsv ] && echo 1 || echo 0`
    \echo Exporting to hackernews.tsv
    \set tsv_file :file_base /hackernews.tsv
    COPY hackernews TO :'tsv_file' ( format 'TabSeparatedWithNames', structure :'structure');
    \! gzip -fk hackernews.tsv
\endif

\if `[ ! -f hackernews.csv ] && echo 1 || echo 0`
    \echo Exporting to hackernews.csv
    \set csv_file :file_base /hackernews.csv
    COPY hackernews TO :'csv_file' ( format 'CSVWithNames', structure :'structure');
    \! gzip -fk hackernews.csv
\endif

\if `[ ! -f hackernews.json ] && echo 1 || echo 0`
    \echo Exporting to hackernews.json
    \set json_file :file_base /hackernews.json
    COPY hackernews TO :'json_file' ( format 'JSONEachRow', structure :'structure');
    \! gzip -fk hackernews.json
\endif

\if `[ ! -f hackernews.parquet ] && echo 1 || echo 0`
    \echo Exporting to hackernews.parquet
    \set parquet_file :file_base /hackernews.parquet
    COPY hackernews TO :'parquet_file' ( format 'parquet', structure :'structure');
\endif

\if `[ ! -f hackernews.arrow ] && echo 1 || echo 0`
    \echo Exporting to hackernews.arrow
    \set arrow_file :file_base /hackernews.arrow
    COPY hackernews TO :'arrow_file' ( format 'arrow', structure :'structure');
\endif

\if `[ ! -f hackernews.avro ] && echo 1 || echo 0`
    \echo Exporting to hackernews.avro
    \set avro_file :file_base /hackernews.avro
    COPY hackernews TO :'avro_file' ( format 'avro', structure :'structure');
\endif
