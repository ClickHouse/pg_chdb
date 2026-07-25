LOAD 'chdb';

/****************************************************************************/
-- Strings.
CREATE TABLE strings (
    t  TEXT    NOT NULL,
    ba BYTEA   NOT NULL,
    n  NAME        NULL
);

INSERT INTO strings
VALUES ('', '', '')
     , ('  ', '   ', NULL)
     , ('hi', '\xdeadbeef', 'yo')
     , ('😃 🐨 🎱', '\x83c2815f9018eb2d4c26dac9d69c4c93ddc7a284', 'big fat name')
     , ('"Bøwie"', '\x9a60f295bcb186a729d04e76377b7f122b2a1dd9', '"ALL CAPS"')
;

-- Execute round-trip to all supported formats. JSON, JSONCompact and
-- JSONColumnsWithMetadata always validate UTF-8, whatever
-- output_format_json_validate_utf8 says, so the bytea columns come back with
-- replacement characters. Protobuf reads a Nullable field holding the empty
-- string back as NULL, so the empty name does not survive:
-- https://github.com/chdb-io/chdb-core/issues/152
CREATE TABLE strings2 (LIKE strings INCLUDING ALL);
\set from_table strings
\set to_table strings2
\set output_file strings.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- String Arrays.
CREATE TABLE string_arrays (
    t  TEXT[]    NOT NULL,
    ba BYTEA[]   NOT NULL,
    n  NAME[]    NOT NULL
);

INSERT INTO string_arrays
VALUES ('{}', '{}', '{}')
     , ('{hi}', '{\xdeadbeef}', '{yo}')
     , ('{hi, NULL}', '{NULL, \xdeadbeef}', '{NULL}')
     , ('{😃 🐨 🎱,"\"GO\""}', '{\xdeadbeef, \x83c2815f9018eb2d4c26dac9d69c4c93ddc7a284}', '{big fat name,NULL}')
;

-- Execute round-trip to all supported formats. Protobuf has no null in a
-- repeated field, so the arrays carrying one come back short.
CREATE TABLE string_arrays2 (LIKE string_arrays INCLUDING ALL);
\set from_table string_arrays
\set to_table string_arrays2
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/strings.tmp 2> /dev/null || true
