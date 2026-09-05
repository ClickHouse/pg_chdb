BEGIN;
SET client_min_messages TO WARNING;

CREATE TYPE http_method AS ENUM(
  'GET', 'HEAD', 'POST', 'PUT', 'DELETE',
  'CONNECT', 'OPTIONS', 'TRACE', 'PATCH', 'QUERY'
);

-- Table name `target` required by util.pgsql/load_target().
CREATE TABLE  target (
    req_id    BIGINT,
    start_at  TIMESTAMPTZ,
    duration  INTEGER,
    resource  TEXT,
    method    http_method,
    node_id   BIGINT,
    response  INTEGER
);

\ir util.pgsql

COPY (SELECT * FROM load_target('logs', 'CSV', 'none', 'logs/logs-2026-08-26.csv', 'logs/logs-2026-08-27.csv', 'logs/logs-2026-08-28.csv')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'CSV', 'gzip', 'logs/logs-2026-08-26.csv.gz', 'logs/logs-2026-08-27.csv.gz', 'logs/logs-2026-08-28.csv.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'JSON', 'none', 'logs/logs-2026-08-26.json', 'logs/logs-2026-08-27.json', 'logs/logs-2026-08-28.json')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'JSON', 'gzip', 'logs/logs-2026-08-26.json.gz', 'logs/logs-2026-08-27.json.gz', 'logs/logs-2026-08-28.json.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'Parquet', 'zstd', 'logs/logs-2026-08-26.parquet', 'logs/logs-2026-08-27.parquet', 'logs/logs-2026-08-28.parquet')) TO STDOUT;

ROLLBACK;
