LOAD 'chdb';

/****************************************************************************/
-- Bit Strings.
CREATE TABLE bits (
    b  BIT       NOT NULL,
    bn BIT(3)    NOT NULL,
    vb varbit(6) NOT NULL
);

INSERT INTO bits
VALUES ('1', '111', '111111')
     , ('0', '000', '000000')
     , ('0', '000', '000000')
;

-- Execute round-trip to all supported formats.
CREATE TABLE bits2 (LIKE bits INCLUDING ALL);
\set from_table bits
\set to_table bits2
\set output_fle bits.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Bit String Arrays
CREATE TABLE bit_arrays (
    b  BIT[]       NOT NULL,
    bn BIT(3)[]    NOT NULL,
    vb varbit(6)[] NOT NULL
);

INSERT INTO bit_arrays
VALUES ('{1}', '{111}', '{111111}')
     , ('{0,1,NULL}', '{000,001,111,110}', '{000000,111001,101010}')
;

-- Execute round-trip to all supported formats.
CREATE TABLE bit_arrays2 (LIKE bit_arrays INCLUDING ALL);
\set from_table bit_arrays
\set to_table bit_arrays2
\i test/utils/round-trip-formats.sql

\set ECHO errors
\set ci ''
\getenv ci CI
SELECT :'ci' = '' AS not_ci \gset
\if :not_ci
\! rm -rf /tmp/bits.tmp
\endif
