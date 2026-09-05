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

COPY (SELECT * FROM load_target('logs', 'Text', 'none', 'logs/logs-2026-08-26.tsv', 'logs/logs-2026-08-27.tsv', 'logs/logs-2026-08-28.tsv')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'CSV', 'none', 'logs/logs-2026-08-26.csv', 'logs/logs-2026-08-27.csv', 'logs/logs-2026-08-28.csv')) TO STDOUT;

ROLLBACK;
