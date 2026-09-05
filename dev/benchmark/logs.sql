BEGIN;
SET client_min_messages TO WARNING;
SET datestyle TO ISO;
SET timezone TO UTC;
\getenv workdir WORKDIR
\set file_base file:// :workdir

LOAD 'chdb_hook';

CREATE TYPE http_method AS ENUM(
  'GET', 'HEAD', 'POST', 'PUT', 'DELETE',
  'CONNECT', 'OPTIONS', 'TRACE', 'PATCH', 'QUERY'
);

CREATE TABLE  logs (
    req_id    BIGINT      PRIMARY KEY,
    start_at  TIMESTAMPTZ NOT NULL,
    duration  INTEGER     NOT NULL,
    resource  TEXT        NOT NULL,
    method                http_method,
    node_id               BIGINT NOT NULL,
    response              INTEGER NOT NULL
);

/*

CREATE TABLE nodes (
    node_id BIGINT PRIMARY KEY,
    name    TEXT   NOT NULL,
    region  TEXT   NOT NULL,
    arch    TEXT   NOT NULL,
    os      TEXT   NOT NULL
);

INSERT INTO nodes
VALUES (1, 'Weeping Somnambulist', 'us-east-1', 'amd64', 'Linux')
     , (2, 'Donager', 'us-east-2', 'amd64', 'Linux')
     , (3, 'Anubis', 'ca-central-1', 'arm64', 'macOS')
     , (4, 'Arbogast', 'ap-northeast-1', 'amd64', 'Windows')
     , (5, 'Barbapiccola', 'us-east-1', 'arm64', 'Linux')
     , (6, 'Rocinante', 'us-east-1', 'arm64', 'Linux')
     , (7, 'Giambattista', 'us-east-1', 'amd64', 'Linux')
     , (8, 'Nauvoo', 'us-east-1', 'arm64', 'Linux')
;
*/

\set products $${widgets, sprockets, services, books, records}$$::TEXT[]
\set profiles $${users, orgs, transactions}$$::TEXT[]

-- Load random words into an array.
SELECT format(
    '$$%s$$::text[]',
    string_to_array(trim(pg_read_file('/usr/share/dict/words')::text, E' \n\r'),E'\n')
) AS words \gset

-- Generate random-ish "log" entries for a given date.
PREPARE insert_logs(date, int) AS
    INSERT INTO logs
    SELECT random(0, +9223372036854775807) AS req_id,
           concat($1 ||'T00:00:00.', floor(random(0, 999999)) || 'Z')::timestamptz + (random(1, 86300) || 's')::interval AS start_at,
           (WITH x(a) AS (select random(x-x+1, 100)) SELECT CASE WHEN a < 95 THEN random(150, 300) WHEN a < 97 THEN random(50, 400) WHEN a < 99 THEN random(30, 900) ELSE random(10, 10000) END FROM x) AS duration,
           (WITH x(a) AS (SELECT random(x-x+0, 1)) SELECT CASE WHEN a = 0 THEN format('/%s/%s', (:products)[random(x-x+1, array_length(:products, 1))], LOWER((:words)[random(1, array_length(:words, 1))])) ELSE format('/%s/%s', (:profiles)[random(x-x+1, array_length(:profiles, 1))], random(x-x+802683, 5739238)) END FROM x) AS resource,
           (WITH x(a) AS (select random(x-x+1, 100)) SELECT CASE WHEN a < 91 THEN 'GET' WHEN a < 97 THEN 'POST' WHEN a < 99 THEN 'PUT' ELSE (ARRAY['HEAD', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE', 'PATCH', 'QUERY'])[random(x-x+1, 7)] END FROM x)::http_method AS method,
           random(1, 8) AS node_id,
           (WITH x(a) AS (select random(x-x+1, 100)) SELECT CASE WHEN a < 95 THEN 200 WHEN a < 97 THEN 201 WHEN a < 99 THEN 204 ELSE (ARRAY[308, 400, 401, 403, 500])[random(x-x+1, 5)] END FROM x) AS response
    FROM generate_series(1, $2) x
;

\set structure 'req_id UInt64, start_at DateTime64(6, ''UTC''), duration UInt32, resource String, method String, node_id UInt64, response UInt16'

/********************* 2026-08-26 *********************/
\set log_date 2026-08-26
\echo 'Inserting logs for 2026-08-26'
TRUNCATE logs;
EXECUTE insert_logs(:'log_date', 10000);

\if `[ ! -f logs-:log_date.tsv ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.tsv
    \set tsv_file :file_base /logs-:log_date.tsv
    COPY logs TO :'tsv_file' ( format 'TabSeparatedWithNames', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.csv ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.csv
    \set csv_file :file_base /logs-:log_date.csv
    COPY logs TO :'csv_file' ( format 'CSVWithNames', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.json ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.json
    \set json_file :file_base /logs-:log_date.json
    COPY logs TO :'json_file' ( format 'JSONEachRow', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.parquet ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.parquet
    \set parquet_file :file_base /logs-:log_date.parquet
    COPY logs TO :'parquet_file' ( format 'parquet', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.arrow ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.arrow
    \set arrow_file :file_base /logs-:log_date.arrow
    COPY logs TO :'arrow_file' ( format 'arrow', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.avro ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.avro
    \set avro_file :file_base /logs-:log_date.avro
    COPY logs TO :'avro_file' ( format 'avro', structure :'structure');
\endif

/********************* 2026-08-27 *********************/
\set log_date 2026-08-27
\echo 'Inserting logs for 2026-08-27'
TRUNCATE logs;
EXECUTE insert_logs(:'log_date', 10000);

\if `[ ! -f logs-:log_date.tsv ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.tsv
    \set tsv_file :file_base /logs-:log_date.tsv
    COPY logs TO :'tsv_file' ( format 'TabSeparatedWithNames', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.csv ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.csv
    \set csv_file :file_base /logs-:log_date.csv
    COPY logs TO :'csv_file' ( format 'CSVWithNames', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.json ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.json
    \set json_file :file_base /logs-:log_date.json
    COPY logs TO :'json_file' ( format 'JSONEachRow', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.parquet ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.parquet
    \set parquet_file :file_base /logs-:log_date.parquet
    COPY logs TO :'parquet_file' ( format 'parquet', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.arrow ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.arrow
    \set arrow_file :file_base /logs-:log_date.arrow
    COPY logs TO :'arrow_file' ( format 'arrow', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.avro ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.avro
    \set avro_file :file_base /logs-:log_date.avro
    COPY logs TO :'avro_file' ( format 'avro', structure :'structure');
\endif

/********************* 2026-08-28 *********************/
\set log_date 2026-08-28
\echo 'Inserting logs for 2026-08-28'
TRUNCATE logs;
EXECUTE insert_logs(:'log_date', 10000);

\if `[ ! -f logs-:log_date.tsv ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.tsv
    \set tsv_file :file_base /logs-:log_date.tsv
    COPY logs TO :'tsv_file' ( format 'TabSeparatedWithNames', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.csv ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.csv
    \set csv_file :file_base /logs-:log_date.csv
    COPY logs TO :'csv_file' ( format 'CSVWithNames', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.json ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.json
    \set json_file :file_base /logs-:log_date.json
    COPY logs TO :'json_file' ( format 'JSONEachRow', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.parquet ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.parquet
    \set parquet_file :file_base /logs-:log_date.parquet
    COPY logs TO :'parquet_file' ( format 'parquet', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.arrow ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.arrow
    \set arrow_file :file_base /logs-:log_date.arrow
    COPY logs TO :'arrow_file' ( format 'arrow', structure :'structure');
\endif

\if `[ ! -f logs-:log_date.avro ] && echo 1 || echo 0`
    \echo Exporting to logs-:log_date.avro
    \set avro_file :file_base /logs-:log_date.avro
    COPY logs TO :'avro_file' ( format 'avro', structure :'structure');
\endif

/********************* Compress *********************/
\! gzip -fk logs-*.tsv logs-*.json logs-*.csv

ROLLBACK;
