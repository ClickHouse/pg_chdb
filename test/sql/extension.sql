SELECT pgchdb_version() ~ '^\d+\.\d+\.\d+$';

SELECT version = pgchdb_version() 
  FROM pg_get_loaded_modules()
 WHERE module_name = 'chdb';
