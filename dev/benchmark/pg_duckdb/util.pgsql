SET client_min_messages TO WARNING;
CREATE EXTENSION IF NOT EXISTS pg_duckdb;

-- Establish average overhead in _overhead.
SELECT clock_timestamp() AS _timing \gset
SELECT clock_timestamp() AS _start_ts \gset
SELECT 1 AS ignore \gset
SELECT clock_timestamp() AS _end_ts \gset

SELECT 1000 * GREATEST(0, extract(epoch FROM LEAST(
    :'_start_ts'::timestamptz - :'_timing'::timestamptz,
    :'_end_ts'::timestamptz   - :'_start_ts'::timestamptz
))) AS _timing1 \gset

SELECT clock_timestamp() AS _timing \gset
SELECT clock_timestamp() AS _start_ts \gset
SELECT 1 AS ignore \gset
SELECT clock_timestamp() AS _end_ts \gset

SELECT 1000 * GREATEST(0, extract(epoch FROM LEAST(
    :'_start_ts'::timestamptz - :'_timing'::timestamptz,
    :'_end_ts'::timestamptz   - :'_start_ts'::timestamptz
))) AS _timing2 \gset

SELECT clock_timestamp() AS _timing \gset
SELECT clock_timestamp() AS _start_ts \gset
SELECT 1 AS ignore \gset
SELECT clock_timestamp() AS _end_ts \gset

SELECT 1000 * GREATEST(0, extract(epoch FROM LEAST(
    :'_start_ts'::timestamptz - :'_timing'::timestamptz,
    :'_end_ts'::timestamptz   - :'_start_ts'::timestamptz
))) AS _timing3 \gset

SELECT avg(y) AS _overhead FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset

-- Assemble select targets.
SELECT string_agg(format('r[%L]::%s', column_name, data_type), ', ' ORDER BY  ordinal_position) AS select_list
  FROM information_schema.columns WHERE table_name = 'target' \gset
