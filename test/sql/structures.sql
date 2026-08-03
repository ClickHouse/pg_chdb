LOAD 'chdb';

/****************************************************************************/
-- Structured types as strings.
CREATE TABLE structures (
    jp   jsonpath NOT NULL,
    xml  XML      NOT NULL,
    j    JSON     NOT NULL,
    jb   JSONB        NULL
);

INSERT INTO structures
VALUES ('$.x', '<html>hi</html>', '{"x": true}', '{"y": false}')
     , ('$', '', 'null', 'null')
     , ('$.x.y[2]', '<p></p>', '42', '42')
     , ('$["😀 😕"]', '<x>😍 😌</x>', '"😝 🤩"', '"🤓 🧐"')
     , ('$', '', '98.6', '98.6')
     , ('$', '', 'true', 'true')
     , ('$', '', '[1, "🖲️", null]', '[1, "🖲️", null]')
;

-- Execute round-trip to all supported formats.
CREATE TABLE structures2 (LIKE structures INCLUDING ALL);
\set from_table structures
\set to_table structures2
\set output_file structures.tmp
\set columns 'jp::text, xml::text, j::text, jb::text'
\i test/utils/round-trip-formats.sql

-- Alas, these formats fail:

-- JSONStringsEachRow
-- JSONCompactStringsEachRow
-- JSONCompactStringsEachRowWithNames
-- JSONCompactStringsEachRowWithNamesAndTypes

-- Details:
-- https://github.com/ClickHouse/ClickHouse/issues/68428#issuecomment-5074490421

/****************************************************************************/
-- Structured types as string arrays.
CREATE TABLE structure_arrays (
    jp   jsonpath[] NOT NULL,
    xml  XML[]      NOT NULL,
    j    JSON[]     NOT NULL,
    jb   JSONB[]    NOT NULL
);

INSERT INTO structure_arrays
VALUES ('{$.x}', '{<html>hi</html>}', '{NULL, "{\"x\": true}"}', '{"{\"y\": false}", NULL}')
     , ('{$}', '{0}', '{42, 98.6, []}', '{42, 98.6, []}')
     , ('{$}', '{0}', '{null}', '{null}')
     , ('{}', '{}', '{}', '{}')
     , ('{$, NULL}', '{NULL}', '{"[1, \"🖲️\", null]"}', '{"[1, \"🖲️\", null]"}')
     , ('{$.x.💿[2], $}', '{"<a id=\"🦁\"/>", ""}', '{"true, {\"x\": 1}"}, ''{"true, {\"x\": 1}"}')
;

-- Execute round-trip to all supported formats.
CREATE TABLE structure_arrays2 (LIKE structure_arrays INCLUDING ALL);
\set from_table structure_arrays
\set to_table structure_arrays2
\set columns 'jp::text[], xml::text[], j::text[], jb::text[]'
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/structures.tmp 2> /dev/null || true
