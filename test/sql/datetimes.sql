LOAD 'chdb';

/****************************************************************************/
-- Dates and times.
CREATE TABLE datetimes (
    ts    TIMESTAMP          NULL,
    tsn   TIMESTAMP(3)       NULL,
    tstz  TIMESTAMPTZ    NOT NULL,
    tstzn TIMESTAMPTZ(4) NOT NULL,
    date  DATE           NOT NULL,
    time  TIME           NOT NULL,
    timen TIME(3)        NOT NULL,
    ttz   TIMETZ         NOT NULL,
    ttzn  TIMETZ(2)      NOT NULL,
    ival  INTERVAL       NOT NULL
);

INSERT INTO datetimes
VALUES ('2026-07-23 20:43:10', '2026-07-23 20:43:27', '2026-07-23 20:43:50+00', '2026-07-23 13:44:46-07', '2026-07-23', '13:45:15', '13:45:24', '13:45:35.306886-07', '13:45:49.17-07', '1 day');
;

-- Execute round-trip to all supported formats. Parquet, Arrow, ArrowStream,
-- ORC, Avro, Protobuf, ProtobufList, MsgPack and BSONEachRow have no column
-- type for a Time64, so those declare the time columns String.
CREATE TABLE datetimes2 (LIKE datetimes INCLUDING ALL);
\set from_table datetimes
\set to_table datetimes2
\set output_file datetimes.tmp
\i test/utils/round-trip-formats.sql

-- Add timestamps with sub-second precision. Protobuf truncates seconds so
-- will fail.
INSERT INTO datetimes
VALUES ('2026-07-23 20:43:10.836612', '2026-07-23 20:43:27.363', '2026-07-23 20:43:50.944042+00', '2026-07-23 13:44:46.8445-07', '2026-07-23', '13:45:15.416013', '13:45:24.282', '13:45:35.306886-07', '13:45:49.17-07', '1 day');
\i test/utils/round-trip-formats.sql

-- Try again with greater time spans, which ORC and Protobuf dislike.
-- Protobuf chokes on dates prior to 1970-01-01, so avoid them. https://github.com/ClickHouse/ClickHouse/issues/111860
INSERT INTO datetimes
VALUES (NULL, NULL, '2299-12-31 23:59:59.999999Z', '1970-01-01 00:00:00Z', '1900-01-01', '00:00:00', '24:00:00', '00:00:00+1559', '24:00:00-1559', '-178000000 years');
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Dates and time arrays.
CREATE TABLE datetime_arrays (
    ts    TIMESTAMP[]      NOT NULL,
    tsn   TIMESTAMP(3)[]   NOT NULL,
    tstz  TIMESTAMPTZ[]    NOT NULL,
    tstzn TIMESTAMPTZ(4)[] NOT NULL,
    date  DATE[]           NOT NULL,
    time  TIME[]           NOT NULL,
    timen TIME(3)[]        NOT NULL,
    ttz   TIMETZ[]         NOT NULL,
    ttzn  TIMETZ(2)[]      NOT NULL,
    ival  INTERVAL[]       NOT NULL
);

INSERT INTO datetime_arrays
VALUES ('{2026-07-23 20:43:10.836612}', '{2026-07-23 20:43:27.363}', '{2026-07-23 20:43:50.944042+00}', '{2026-07-23 13:44:46.8445-07}', '{2026-07-23}', '{13:45:15.416013}', '{13:45:24.282}', '{13:45:35.306886-07}', '{13:45:49.17-07}', '{1 day}')
     , ('{1900-01-01 00:00:00, 2299-12-31 23:59:59.999999}', '{}', '{1900-01-01 00:00:00Z, 2299-12-31 23:59:59.999999Z}', '{NULL}', '{1900-01-01, 2299-12-31}', '{00:00:00, 24:00:00}', '{NULL}', '{00:00:00+1559, 24:00:00-1559}', '{09:23:23Z}', '{-178000000 years, NULL}')
;

-- Execute round-trip to all supported formats. ORC reads a year 2299 timestamp
-- back out of DateTime64's range and Protobuf overflows converting one, as
-- above, and Protobuf has no null in a repeated field either.
CREATE TABLE datetime_arrays2 (LIKE datetime_arrays INCLUDING ALL);
\set from_table datetime_arrays
\set to_table datetime_arrays2
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/datetimes.tmp 2> /dev/null || true
