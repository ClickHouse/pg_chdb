-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION chdb" to load this file. \quit

CREATE FUNCTION pgchdb_version() RETURNS TEXT
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

-- Execute query against temporary chDB instance, mapping the resulting data
-- types to Postgres types named in caller's column definition list, e.g.
-- SELECT FROM chdb_query('SELECT a, b FROM t') AS (a int, b text);
CREATE FUNCTION chdb_query(TEXT)
RETURNS SETOF record
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

-- Make sure PUBLIC can't run arbitrary queries; roles must be granted
-- explicit access.
REVOKE EXECUTE ON FUNCTION chdb_query(text) FROM PUBLIC;
