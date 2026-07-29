LOAD 'chdb';

/****************************************************************************/
-- oid8. Values above int8 range need quoting, else Postgres reads them as
-- numeric, which has no implicit cast to oid8.
CREATE TABLE oid8s (
    o8  OID8 NOT NULL,
    n8  OID8     NULL
);

INSERT INTO oid8s
VALUES (0, 0)
     , (0, NULL)
     , (4294967295, 4294967296)
     , ('18446744073709551615', '18446744073709551615')
;

-- Guard against an empty table round-tripping vacuously.
SELECT COUNT(*) FROM oid8s;

-- Execute round-trip to all supported formats.
-- Protobuf currently fails: https://github.com/chdb-io/chdb-core/issues/152
CREATE TABLE oid8s2 (LIKE oid8s INCLUDING ALL);
\set from_table oid8s
\set to_table oid8s2
\set output_fle oid8s.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- oid8 Arrays.
CREATE TABLE oid8_arrays (
    o8  OID8[] NOT NULL
);

INSERT INTO oid8_arrays
VALUES ('{0}')
     , ('{}')
     , ('{4294967295,4294967296}')
     , ('{18446744073709551615, NULL}')
;

SELECT COUNT(*) FROM oid8_arrays;

CREATE TABLE oid8_arrays2 (LIKE oid8_arrays INCLUDING ALL);
\set from_table oid8_arrays
\set to_table oid8_arrays2
\i test/utils/round-trip-formats.sql
\! rm -rf test/oid8s.tmp
