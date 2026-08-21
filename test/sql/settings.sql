-- Load chdb and chdb_hook to ensure they don't conflict.
LOAD 'chdb';
LOAD 'chdb_hook';

PREPARE show_all AS
    SELECT 'chdb' AS extension,
        current_setting('chdb.max_memory') AS memory,
        current_setting('chdb.max_threads') AS threads,
        current_setting('chdb.max_parsing_threads') AS parsers
    UNION SELECT 'chdb_hook',
        current_setting('chdb_hook.max_memory'),
        current_setting('chdb_hook.max_threads'),
        current_setting('chdb_hook.max_parsing_threads')
;

PREPARE show_chdb(bool) AS
 SELECT * FROM chdb_query(
    format($$
        SELECT name, %s AS value
        FROM system.settings
        WHERE name IN (
            'max_memory_usage', 'max_threads', 'max_parsing_threads',
            'allow_experimental_nullable_tuple_type',
            'output_format_native_encode_types_in_binary_format',
            'output_format_native_write_json_as_string'
        )
        ORDER BY name
    $$,
    -- max_threads maxes out at the max hardware threads, so if we've set it
    -- to the max value ($1 = true), just report it as "MAX" if it's not zero.
    CASE WHEN $1
        THEN $$CASE WHEN name = 'max_threads' AND value <> '0' THEN 'MAX' ELSE replaceRegexpOne(value, '[(][0-9]+[)]$', '') END$$
        ELSE $$replaceRegexpOne(value, '[(][0-9]+[)]$', '')$$
    END
    )
) AS (name text, value text);

-- Look at the default values;
EXECUTE show_all;
EXECUTE show_chdb(false);

-- Set integer values.
SET chdb.max_memory = 5000;
SET chdb.max_threads = 42;
SET chdb.max_parsing_threads = 12;
SET chdb_hook.max_memory = 100;
SET chdb_hook.max_threads = 12;
SET chdb_hook.max_parsing_threads = 6;
EXECUTE show_all;
EXECUTE show_chdb(false);

-- And again using size syntax for the memory
SET chdb.max_memory = '100MB';
SET chdb.max_threads = 88;
SET chdb.max_parsing_threads = 10;
SET chdb_hook.max_memory = '1 GB';
SET chdb_hook.max_threads = 900;
SET chdb_hook.max_parsing_threads = 1000;
EXECUTE show_all;
EXECUTE show_chdb(false);

-- Set max values.
SET chdb.max_memory = 65535;
SET chdb.max_threads = 65535;
SET chdb.max_parsing_threads = 65535;
SET chdb_hook.max_memory = 65535;
SET chdb_hook.max_threads = 65535;
SET chdb_hook.max_parsing_threads = 65535;
EXECUTE show_all;
EXECUTE show_chdb(true);

-- Set invalid values.
SET chdb.max_memory = -1;
SET chdb.max_threads = -1;
SET chdb.max_parsing_threads = -1;
SET chdb_hook.max_memory = -1;
SET chdb_hook.max_threads = -1;
SET chdb_hook.max_parsing_threads = -1;
SET chdb.max_memory = 65536;
SET chdb.max_threads = 65536;
SET chdb.max_parsing_threads = 65536;
SET chdb_hook.max_memory = 65536;
SET chdb_hook.max_threads = 65536;
SET chdb_hook.max_parsing_threads = 65536;
