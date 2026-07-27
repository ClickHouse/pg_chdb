-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION chdb" to load this file. \quit

CREATE FUNCTION pgchdb_version() RETURNS TEXT
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;
