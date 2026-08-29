LOAD 'chdb_hook';

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

/****************************************************************************/
CREATE TABLE intervals (
    y   INTERVAL NOT NULL,
    q   INTERVAL NOT NULL,
    mon INTERVAL NOT NULL,
    w   INTERVAL NOT NULL,
    d   INTERVAL NOT NULL,
    h   INTERVAL NOT NULL,
    mi  INTERVAL NOT NULL,
    s   INTERVAL NOT NULL,
    ms  INTERVAL NOT NULL,
    us  INTERVAL NOT NULL,
    ns  INTERVAL NOT NULL
);

INSERT INTO intervals
VALUES ('6 years', '9 months', '-5 months', '14 days', '-3 days', '4 hours', '-90 minutes', '2 sec', '0.25 sec', '-0.000001 sec', '1.000002 sec');

\set interval_structure 'y IntervalYear, q IntervalQuarter, mon IntervalMonth, w IntervalWeek, d IntervalDay, h IntervalHour, mi IntervalMinute, s IntervalSecond, ms IntervalMillisecond, us IntervalMicrosecond, ns IntervalNanosecond'

CREATE TABLE intervals2 (LIKE intervals INCLUDING ALL);
COPY intervals TO 'file:///tmp/datetimes.tmp'
     (format 'TabSeparated', structure :'interval_structure');
COPY intervals2 FROM 'file:///tmp/datetimes.tmp'
     (format 'TabSeparated', structure :'interval_structure');

SELECT count(*) AS intervals_mismatch
  FROM (SELECT * FROM intervals EXCEPT ALL SELECT * FROM intervals2) x;

-- Months mixed with days, or a value which doesn't fit destination interval type.
CREATE TABLE misfits (iv INTERVAL NOT NULL);
INSERT INTO misfits VALUES ('1 mon 1 day');
COPY misfits TO 'file:///tmp/datetimes.tmp'
     (format 'TabSeparated', structure 'iv IntervalMonth');
TRUNCATE misfits;
INSERT INTO misfits VALUES ('1.5 days');
COPY misfits TO 'file:///tmp/datetimes.tmp'
     (format 'TabSeparated', structure 'iv IntervalDay');

-- Reading same ticks truncates nanoseconds to microseconds in Postgres
CREATE TABLE ticks (n INT8 NOT NULL);
CREATE TABLE tocks (iv INTERVAL NOT NULL);
INSERT INTO ticks VALUES (1500), (-1500);
COPY ticks TO 'file:///tmp/datetimes.tmp' (format 'TabSeparated', structure 'n Int64');
COPY tocks FROM 'file:///tmp/datetimes.tmp'
     (format 'TabSeparated', structure 'n IntervalNanosecond');
SELECT iv FROM tocks ORDER BY iv;

TRUNCATE ticks;
INSERT INTO ticks VALUES (9223372036854775807);
COPY ticks TO 'file:///tmp/datetimes.tmp' (format 'TabSeparated', structure 'n Int64');
COPY tocks FROM 'file:///tmp/datetimes.tmp'
     (format 'TabSeparated', structure 'n IntervalYear');

\set ECHO errors
\! rm -rf /tmp/datetimes.tmp 2> /dev/null || true
