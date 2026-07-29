LOAD 'chdb';

/****************************************************************************/
-- Fixed-length strings.
CREATE TABLE fixies (
    cr  character(6) NOT NULL,
    ch  char(12)     NOT NULL,
    bp  bpchar       NOT NULL,
    pbn bpchar(8)        NULL
);

INSERT INTO fixies
VALUES ('      ', '            ', ' ', '        ')
     , ('', '', '', NULL)
     , ('hi  ', 'hi   ', '', NULL)
     , ('😃 🐨 🎱', '是无效的命令', '否', '未定义的参数')
;

-- Execute round-trip to all supported formats.
CREATE TABLE fixies2 (LIKE fixies INCLUDING ALL);
\set output_fle fixies.tmp
\set from_table fixies
\set to_table fixies2
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Fixed-length string Arrays.
CREATE TABLE fixie_arrays (
    cr  character(6)[] NOT NULL,
    ch  char(12)[]     NOT NULL,
    bp  bpchar[]       NOT NULL,
    pbn bpchar(8)[]    NOT NULL
);

INSERT INTO fixie_arrays
VALUES ('{"      "}', '{"            "}', '{" "}', '{"        "}')
     , ('{""}', '{""}', '{""}', '{""}')
     , ('{😃 🐨 🎱, NULL}', '{NULL, 是无效的命令}', '{NULL}', '{未定义的参数, NULL}')
     , ('{"Bøwie", "\"GO\""}', '{否,模板}', '{x,y,z,NULL}', '{"ALL CAPS"}')
;

-- Execute round-trip to all supported formats.
CREATE TABLE fixie_arrays2 (LIKE fixie_arrays INCLUDING ALL);
\set from_table fixie_arrays
\set to_table fixie_arrays2
\i test/utils/round-trip-formats.sql

\set ECHO errors
\set ci ''
\getenv ci CI
SELECT :'ci' = '' AS not_ci \gset
\if :not_ci
\! rm -rf /tmp/fixies.tmp
\endif
