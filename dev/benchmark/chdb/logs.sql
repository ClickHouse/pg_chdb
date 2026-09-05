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

COPY (SELECT * FROM load_target('logs', 'TabSeparatedWithNames', 'none', 'logs/logs-*.tsv')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'TabSeparatedWithNames', 'gzip', 'logs/logs-*.tsv.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'CSVWithNames', 'none', 'logs/logs-*.csv')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'CSVWithNames', 'gzip', 'logs/logs-*.csv.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'JSONEachRow', 'none', 'logs/logs-*.json')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'JSONEachRow', 'gzip', 'logs/logs-*.json.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'Parquet', 'zstd', 'logs/logs-*.parquet')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'Arrow', 'lz4', 'logs/logs-*.arrow')) TO STDOUT;
COPY (SELECT * FROM load_target('logs', 'Avro', 'snappy', 'logs/logs-*.avro')) TO STDOUT;

ROLLBACK;
