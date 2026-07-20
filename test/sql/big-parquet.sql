LOAD 'chdb';
SET datestyle = 'ISO';
SET session timezone = 'UTC'; -- https://github.com/chdb-io/chdb-core/issues/143

\getenv test_dir PG_ABS_SRCDIR
\set parquet_file file:// :test_dir /big.tmp/big.parquet

CREATE TYPE http_method AS ENUM(
  'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT',
   'OPTIONS', 'TRACE', 'PATCH', 'QUERY'
);

\set ECHO errors
SELECT current_setting('server_version_num')::int < 170000 AS pg16 \gset
\if :pg16
CREATE OR REPLACE FUNCTION random(min bigint, max bigint) RETURNS bigint LANGUAGE SQL volatile AS $$
    SELECT random() * (max-min) + min;
$$;
\endif
\set ECHO all

CREATE TABLE  logs (
    req_id    BIGINT,
    start_at  TIMESTAMP,
    duration  INTEGER,
    resource  TEXT,
    method    http_method,
    node_id   BIGINT,
    response  INTEGER
);

-- Fill the table with ca 100MB of records.
INSERT INTO logs
SELECT random(0, +9223372036854775807),
       concat('2025-12-19 10:42:00.', floor(random(0, 999999)))::timestamp - (random(1, 86400 * 14) || 's')::interval,
       random(1, 500) AS duration,
       (ARRAY['/profile', '/users', '/users/1321945', '/users/283434', '/users/802683', '/users/1739238', '/users/7392323', '/widgets', '/search', '/search', '/search', '/widgets/omnis', '/widgets/natus', '/widgets/voluptatem', '/widgets/totam', '/widgets/aperiam'])[random(1, 15)],
       (WITH x(a) AS (select random(x-x+1, 100)) SELECT CASE WHEN a < 91 THEN 'GET' WHEN a < 97 THEN 'POST' WHEN a < 99 THEN 'PUT' ELSE (ARRAY['HEAD', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE', 'PATCH', 'QUERY'])[random(x-x+1, 7)] END FROM x)::http_method,
       random(1, 8) AS node_id,
       (WITH x(a) AS (select random(x-x+1, 100)) SELECT CASE WHEN a < 95 THEN 200 WHEN a < 97 THEN 201 WHEN a < 99 THEN 204 ELSE (ARRAY[308, 400, 401, 403, 500])[random(x-x+1, 5)] END FROM x)
-- FROM generate_series(1, 10) x;
FROM generate_series(1, 1260000) x;

SELECT pg_size_pretty(pg_total_relation_size('logs'));

-- Copy out the data
COPY logs TO :'parquet_file' (structure $$
    req_id    UInt64,
    start_at  DateTime64(6, 'UTC'),
    duration  UInt16,
    resource  String,
    method    String,
    node_id   UInt32,
    response  UInt16
$$);

-- Load it back in.
CREATE TABLE imported_logs (LIKE logs INCLUDING ALL);
COPY imported_logs FROM :'parquet_file';

-- They should be the same
SELECT * FROM logs
EXCEPT ALL
SELECT * FROM imported_logs;

\! rm -rf test/big.tmp
