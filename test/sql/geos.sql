LOAD 'chdb_hook';

/****************************************************************************/
-- Geometric types.
CREATE TABLE geos (
    p   point    NOT NULL,
    line line    NOT NULL,
    lseg lseg    NOT NULL,
    box  box     NOT NULL,
    path path    NOT NULL,
    poly polygon NOT NULL,
    cir  circle  NOT NULL
);

INSERT INTO geos
VALUES ('0,0', '(1,1),(2,2)', '((11,11),(12,12))', '((11,11),(13,13))', '((11,12),(13,13),(14,14))', '((11,12),(13,13),(14,14))', '1,1,1')
     , ('(11,nan)', '{nan, 1, nan}', '((11,nan),(nan,12))', '((nan,11),(13,13))', '((11,nan),(13,13),(14,14))', '((11,12),(13,13),(14,nan))', '<(500,500),500>')
     , ('(11,nan)', '{nan, 1, nan}', '((11,nan),(nan,12))', '((nan,11),(13,13))', '[(11,12),(13,13),(14,14)]', '((11,12),(13,13),(14,nan))', '(0,0),1')
;

-- Execute round-trip to all supported formats.
CREATE TABLE geos2 (LIKE geos INCLUDING ALL);
\set from_table geos
\set to_table geos2
\set output_file geos.tmp
\set columns 'p::text, line::text, lseg::text, box::text, path::text, poly::text, cir::text'
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Nullable geometric types. NULL polygon, path or lseg crosses as empty
-- ring or line, ClickHouse rejecting Nullable on implicit Array.
CREATE TABLE geo_nulls (
    p   point,
    line line,
    lseg lseg,
    box  box,
    path path,
    poly polygon,
    cir  circle
);

INSERT INTO geo_nulls
VALUES ('0,0', '(1,1),(2,2)', '((11,11),(12,12))', '((11,11),(13,13))', '((11,12),(13,13),(14,14))', '((11,12),(13,13),(14,14))', '1,1,1')
     , (NULL, NULL, NULL, NULL, NULL, NULL, NULL)
;

-- Execute round-trip to all supported formats.
-- Protobuf reads a Nullable field holding its default back as NULL, so the
-- point at the origin does not survive:
-- https://github.com/chdb-io/chdb-core/issues/152
CREATE TABLE geo_nulls2 (LIKE geo_nulls INCLUDING ALL);
\set from_table geo_nulls
\set to_table geo_nulls2
\set columns 'p::text, line::text, lseg::text, box::text, path::text, poly::text, cir::text'
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Geometric type arrays.
CREATE TABLE geo_arrays (
    p   point[]    NOT NULL,
    line line[]    NOT NULL,
    lseg lseg[]    NOT NULL,
    box  box[]     NOT NULL,
    path path[]    NOT NULL,
    poly polygon[] NOT NULL,
    cir  circle[]  NOT NULL
);

-- Postgres box arrays use ; as a delimiter.
INSERT INTO geo_arrays
VALUES ('{"0,0"}', '{"(1,1),(2,2)"}', '{"((11,11),(12,12))"}', '{"((11,11),(13,13))"}', '{"((11,12),(13,13),(14,14))"}', '{"((11,12),(13,13),(14,14))"}', '{"1,1,1"}')
     , ('{"(11,nan)", NULL}', '{NULL, "{nan, 1, nan}"}', '{NULL}', '{"((nan,11),(13,13))"; NULL}', '{NULL, "((11,nan),(13,13),(14,14))"}', '{"((11,12),(13,13),(14,nan))", NULL}', '{NULL}')
;

-- Execute round-trip to all supported formats. Parquet loses the null map of
-- the Nullable Point the array holds, as above, and Protobuf has no null in a
-- repeated field, so the arrays carrying one come back short.
CREATE TABLE geo_arrays2 (LIKE geo_arrays INCLUDING ALL);
\set from_table geo_arrays
\set to_table geo_arrays2
\set columns 'p::text[], line::text[], lseg::text[], box::text[], path::text[], poly::text[], cir::text[]'
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/geos.tmp 2> /dev/null || true
