LOAD 'chdb';

/****************************************************************************/
-- Network Addresses.
CREATE TABLE nets (
    inet INET     NOT NULL,
    cidr CIDR     NOT NULL,
    mac  MACADDR  NOT NULL,
    mac8 MACADDR8 NOT NULL
);

INSERT INTO nets
VALUES ('1.2.6.4/16', '121.111.63.82', '22:00:5c:08:55:08', '08:00:2b:01:02:03:04:05')
     , ('89.225.196.191', '192.168.1.0/24', '08:00:2b:01:02:03', '22:00:5c:08:55:08:01:02')
     , ('::4:3:2:0/24', '1.2.6.4', '01:02:03:04:05:06', '00:01:03:86:1c:ba')
;

-- Execute round-trip to all supported formats.
CREATE TABLE nets2 (LIKE nets INCLUDING ALL);
\set from_table nets
\set to_table nets2
\set output_file nets.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Network Address Arrays.
CREATE TABLE net_arrays (
    inet INET[]     NOT NULL,
    cidr CIDR[]     NOT NULL,
    mac  MACADDR[]  NOT NULL,
    mac8 MACADDR8[] NOT NULL
);

INSERT INTO net_arrays
VALUES ('{1.2.6.4/16}', '{121.111.63.82}', '{22:00:5c:08:55:08}', '{08:00:2b:01:02:03:04:05}')
     , ('{89.225.196.191, NULL}', '{NULL}', '{NULL, 08:00:2b:01:02:03}', '{22:00:5c:08:55:08:01:02}')
     , ('{::4:3:2:0/24, 126::1}', '{1.2.6.4, 126::1}', '{01:02:03:04:05:06, 02:03:04:05:06:07}', '{00:01:03:86:1c:ba, 08002b-010203}')
;

-- Execute round-trip to all supported formats. Protobuf has no null in a
-- repeated field, so the arrays carrying one come back short.
CREATE TABLE net_arrays2 (LIKE net_arrays INCLUDING ALL);
\set from_table net_arrays
\set to_table net_arrays2
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/nets.tmp 2> /dev/null || true
