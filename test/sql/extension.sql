SELECT pgchdb_version() ~ '^\d+\.\d+\.\d+$';

\set ECHO errors
SELECT current_setting('server_version_num')::int < 180000 AS pg17 \gset
\if :pg17
\echo 'SKIP: pg_get_loaded_modules() not defined prior to Postgres 18'
\quit
\endif
\set ECHO all

SELECT version = pgchdb_version() 
  FROM pg_get_loaded_modules()
 WHERE module_name = 'chdb';
