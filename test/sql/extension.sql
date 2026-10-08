SET DateStyle = 'ISO, MDY';
CREATE EXTENSION IF NOT EXISTS chdb_hook;

----------------------------------------------------------------------------
-- pgchdb_version and chdb_hook_version()
----------------------------------------------------------------------------
SELECT pgchdb_version() ~ '^\d+\.\d+\.\d+$';
SELECT chdb_hook_version() = pgchdb_version();

-- version should be the same as pg_get_loaded_modules() version.
\set ECHO errors
\echo 'SELECT version = pgchdb_version() AS chdb, version = chdb_hook_version() AS hook'
\echo '  FROM pg_get_loaded_modules()'
\echo ' WHERE module_name IN (''chdb'', ''chdb_hook'');'
SELECT current_setting('server_version_num')::int >= 180000 AS pg18 \gset
\if :pg18
-- Compare version strings.
SELECT version = pgchdb_version() AS chdb, version = chdb_hook_version() AS hook
  FROM pg_get_loaded_modules()
 WHERE module_name IN ('chdb', 'chdb_hook');
\else
-- No pg_get_loaded_modules(), just fake it.
\echo ' chdb | hook '
\echo '------+------'
\echo ' t    | t'
\echo ' t    | t'
\echo '(2 rows)'
\echo ''
\endif
\set ECHO all

-- Both chdb and chdb_hook should be listed in pg_available_extensions with
-- their x.y versions.
SELECT name,
       default_version = regexp_replace(pgchdb_version(), '\.\d+$', '')    AS chdb,
       default_version = regexp_replace(chdb_hook_version(), '\.\d+$', '') AS chdb_hook
  FROM pg_available_extensions
 WHERE name IN ('chdb', 'chdb_hook')
 ORDER BY name;

----------------------------------------------------------------------------
-- chdb_query
----------------------------------------------------------------------------
-- Should fail with no definition list.
SELECT * FROM chdb_query('SELECT 1');
SELECT chdb_query('SELECT 1');

-- Should fail with column count mismatch.
SELECT * FROM chdb_query('SELECT 1') AS (a int, b text);
SELECT * FROM chdb_query('SELECT 1, 2') AS (a int);
SELECT * FROM chdb_query('SELECT 1 WHERE 0') AS (x int, y text);

-- Should fail with column type mismatch.
SELECT * FROM chdb_query('SELECT ''26.7.2.1''') AS (version int);

-- Working examples.
SELECT * FROM chdb_query('SELECT ''26.7.2.1''') AS (version text);
SELECT * FROM chdb_query('SELECT 42, ''26.7.2.1''') AS (id int, version text);
SELECT * FROM chdb_query(
    'SELECT number AS n, number * number FROM numbers(5) ORDER BY n'
) AS (n int2, p int);

SELECT * FROM chdb_query(
    'SELECT toInt32(number) AS n, toString(number) AS s FROM numbers(3) ORDER BY n'
) AS (n int, s text);

-- Various types.
SELECT * FROM chdb_query($$
    SELECT number,
           number + 2147483647,
           toDecimal64(concat('1.5241578753238836', number), 17),
           number * 98.6,
           number * pi(),
           'num_' || number,
           toDate32('2025-12-1' || number),
           toDateTime64('2025-12-19 10:42:00.00' || number, 3, 'UTC'),
           number % 2 = 0,
           toIPv4('1.2.3.' || number),
           toUUID('61f0c404-5cb3-11e7-907b-a6006ad3dba' || number)
      FROM numbers(4)
     ORDER BY number
$$) AS (
  integer int,
  int64   int8,
  decimal numeric,
  float32 float4,
  float64 float8,
  string  text,
  date    date,
  dt64    timestamptz,
  even    bool,
  ipv4    inet,
  uuid    uuid
);

-- Clean up after any previous failed run.
SET client_min_messages = error;
DROP ROLE IF EXISTS chdb_not_querier;
DROP ROLE IF EXISTS chdb_yes_querier;
RESET client_min_messages;
CREATE ROLE chdb_not_querier;
CREATE ROLE chdb_yes_querier;
GRANT EXECUTE ON FUNCTION chdb_query(text) TO chdb_yes_querier;

-- A role not granted execute on chdb_query() should fail.
SET ROLE chdb_not_querier;
SELECT * FROM chdb_query('SELECT 1') AS (x int);

-- But it should work if we grant it.
SET ROLE chdb_yes_querier;
SELECT * FROM chdb_query('SELECT 1') AS (x int);

RESET ROLE;
