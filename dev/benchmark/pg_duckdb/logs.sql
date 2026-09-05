BEGIN;
SET client_min_messages TO WARNING;

CREATE TABLE target (
    req_id    BIGINT,
    start_at  TIMESTAMPTZ,
    duration  INTEGER,
    resource  TEXT,
    method    TEXT,
    node_id   BIGINT,
    response  INTEGER
);

\ir util.pgsql
\set base_url s3://chdb-lakedata-public/logs

/***************************************************************************/
-- CSV
\set url1 :base_url/logs-2026-08-26.csv
\set url2 :base_url/logs-2026-08-27.csv
\set url3 :base_url/logs-2026-08-28.csv

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url1', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url2', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url3', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url1', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url2', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url3', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url1', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url2', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url3', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'logs', 'CSV', 'none', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- Gzip CSV
\set url1 :base_url/logs-2026-08-26.csv.gz
\set url2 :base_url/logs-2026-08-27.csv.gz
\set url3 :base_url/logs-2026-08-28.csv.gz

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url1', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url2', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url3', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url1', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url2', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url3', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url1', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url2', header => true) r;
INSERT INTO target SELECT :select_list FROM read_csv(:'url3', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'logs', 'CSV', 'gzip', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- JSON
\set url1 :base_url/logs-2026-08-26.json
\set url2 :base_url/logs-2026-08-27.json
\set url3 :base_url/logs-2026-08-28.json

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'logs', 'JSON', 'none', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- JSON gzip
\set url1 :base_url/logs-2026-08-26.json.gz
\set url2 :base_url/logs-2026-08-27.json.gz
\set url3 :base_url/logs-2026-08-28.json.gz

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_json(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'logs', 'JSON', 'gzip', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- Parquet
\set url1 :base_url/logs-2026-08-26.parquet
\set url2 :base_url/logs-2026-08-27.parquet
\set url3 :base_url/logs-2026-08-28.parquet

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_parquet(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_parquet(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_parquet(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_parquet(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_parquet(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_parquet(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_parquet(:'url1') r;
INSERT INTO target SELECT :select_list FROM read_parquet(:'url2') r;
INSERT INTO target SELECT :select_list FROM read_parquet(:'url3') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'logs', 'Parquet', 'zstd', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

ROLLBACK;
