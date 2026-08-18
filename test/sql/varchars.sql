LOAD 'chdb_hook';

/****************************************************************************/
-- Variable length strings.
CREATE TABLE varchars (
    vc  VARCHAR    NOT NULL,
    vcn VARCHAR(8) NOT NULL,
    bc  VARBIT     NOT NULL,
    bcn VARBIT(4)  NOT NULL
);

INSERT INTO varchars
VALUES ('', '', '', '')
     , ('   ', '        ', '10100101', '1010')
     , ('hi there', 'hi you', '0', '0101')
     , ('😃 🐨 🎱', '是无效的命令', '1', '1100')
;

-- Execute round-trip to all supported formats.
CREATE TABLE varchars2 (LIKE varchars INCLUDING ALL);
\set from_table varchars
\set to_table varchars2
\set output_file varchars.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Variable length string arrays.
CREATE TABLE varchar_arrays (
    vc  VARCHAR[]    NOT NULL,
    vcn VARCHAR(8)[] NOT NULL,
    bc  VARBIT[]     NOT NULL,
    bcn VARBIT(4)[]  NOT NULL
);

INSERT INTO varchar_arrays
VALUES ('{}', '{}', '{}', '{}')
     , ('{   }', '{        }', '{10100101}', '{1010}')
     , ('{hi there, NULL}', '{NULL, hi you}', '{NULL, 0, 1}', '{0101, 0011}')
     , ('{😃 🐨 🎱}', '{是无效的命令}', '{1, NULL}', '{1100}')
;

-- Execute round-trip to all supported formats. Protobuf has no null in a
-- repeated field, so the arrays carrying one come back short.
CREATE TABLE varchar_arrays2 (LIKE varchar_arrays INCLUDING ALL);
\set from_table varchar_arrays
\set to_table varchar_arrays2
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/varchars.tmp 2> /dev/null || true
