LOAD 'chdb';

/****************************************************************************/
-- Maps, read only. No Postgres type maps to Map, and the encoder has no arm
-- for composite Datums, so pg_chdb sees a Map only when a structure option
-- names one. That rules out COPY TO, hence no round trip here.
CREATE TYPE kv AS (k text, v bigint);
CREATE TYPE ikv AS (k bigint, v text);
CREATE TYPE akv AS (k text, v bigint[]);

-- Copy the corpus to /tmp, where the server definitely has read access.
\! cp -f test/corpus/maps.jsonl /tmp/chdb-maps.jsonl
\set maps_json file:///tmp/chdb-maps.jsonl

-- A Map arrives as an array of its key/value pairs.
CREATE TABLE maps (id int, m kv[]);
COPY maps FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, m Map(String, Int64)');
SELECT id, array_dims(m), m FROM maps ORDER BY id;

-- Array(Tuple(K, V)) must decode to the same thing, as must a LowCardinality
-- key. Both queries return no rows.
CREATE TABLE tuples (LIKE maps);
COPY tuples FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, t Array(Tuple(String, Int64))');
SELECT * FROM maps EXCEPT ALL SELECT * FROM tuples;

TRUNCATE tuples;
COPY tuples FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, m Map(LowCardinality(String), Int64)');
SELECT * FROM maps EXCEPT ALL SELECT * FROM tuples;

/****************************************************************************/
-- A Nullable value crosses as a NULL field. ClickHouse rejects a Nullable key
-- and a Nullable Map, so a missing pair and a NULL map cannot be expressed.
CREATE TABLE null_maps (id int, n kv[]);
COPY null_maps FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, n Map(String, Nullable(Int64))');
SELECT id, n FROM null_maps ORDER BY id;

/****************************************************************************/
-- Keys need not be strings.
CREATE TABLE int_keys (id int, i ikv[]);
COPY int_keys FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, ik Map(Int64, String)');
SELECT id, i FROM int_keys ORDER BY id;

-- An array value nests inside the pair.
CREATE TABLE array_values (id int, a akv[]);
COPY array_values FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, av Map(String, Array(Int64))');
SELECT id, a FROM array_values ORDER BY id;

-- Array(Map) spans two Postgres dimensions, so its maps must be of equal
-- length for the array to be rectangular.
CREATE TABLE map_arrays (id int, am kv[]);
COPY map_arrays FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, am Array(Map(String, Int64))');
SELECT id, array_dims(am), am FROM map_arrays ORDER BY id;

/****************************************************************************/
-- The target composite must match the pair.
CREATE TYPE wkv AS (k text, v bigint, w int);
CREATE TABLE bad_width (id int, m wkv[]);
COPY bad_width FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, m Map(String, Int64)');

CREATE TYPE tkv AS (k text, v text);
CREATE TABLE bad_value (id int, m tkv[]);
COPY bad_value FROM :'maps_json' (format 'JSONEachRow', structure 'id Int32, m Map(String, Int64)');

\set ECHO errors
\set ci ''
\getenv ci CI
SELECT :'ci' = '' AS not_ci \gset
\if :not_ci
\! rm -f /tmp/chdb-maps.jsonl
\endif
