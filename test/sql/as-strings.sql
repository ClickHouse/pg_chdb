LOAD 'chdb';

/****************************************************************************/
-- Other things as strings.
CREATE TABLE as_strings (
    ival INTERVAL NOT NULL,
    tsv  tsvector NOT NULL,
    tsq  tsquery  NOT NULL,
    mon  money    NOT NULL
);

INSERT INTO as_strings
VALUES ('02:00:00', 'a fat cat', 'fat & rat', '100')
     , ('0', '', 'x', '0')
     , ('10d', 'winter party', 'fat:AB & cat', '-20')
;

-- Execute round-trip to all supported formats.
CREATE TABLE as_strings2 (LIKE as_strings INCLUDING ALL);
\set from_table as_strings
\set to_table as_strings2
\set output_fle as_strings.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Other arrays of things.
CREATE TABLE as_string_arrays (
    ival INTERVAL[] NOT NULL,
    tsv  tsvector[] NOT NULL,
    tsq  tsquery[]  NOT NULL,
    mon  money[]    NOT NULL
);

INSERT INTO as_string_arrays
VALUES ('{02:00:00}', '{a fat cat}', '{fat & rat}', '{100}')
     , ('{0}', '{}', '{x}', '{0}')
     , ('{0}', '{}', '{x}', '{0}')
     , ('{0, NULL}', '{NULL}', '{NULL, x}', '{NULL, 0}')
     , ('{10d, 5s}', '{fat cat, ❄️ party}', '{fat:AB & cat, ❄️}', '{-20}')
;

-- Execute round-trip to all supported formats.
CREATE TABLE as_string_arrays2 (LIKE as_string_arrays INCLUDING ALL);
\set from_table as_string_arrays
\set to_table as_string_arrays2
\i test/utils/round-trip-formats.sql
\! rm -rf test/as_strings.tmp
