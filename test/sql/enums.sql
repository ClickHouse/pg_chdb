LOAD 'chdb';

/****************************************************************************/
-- Enums.
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TYPE dow AS ENUM ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
CREATE TABLE enums (
    dow  dow  NOT NULL,
    mood mood NOT NULL
);

INSERT INTO enums
VALUES ('Sun', 'ok')
     , ('Mon', 'sad')
     , ('Fri', 'happy')
;

-- Execute round-trip to all supported formats.
CREATE TABLE enums2 (LIKE enums INCLUDING ALL);
\set from_table enums
\set to_table enums2
\set output_file enums.tmp
\i test/utils/round-trip-formats.sql

/****************************************************************************/
-- Enum Arrays.
CREATE TABLE enum_arrays (
    dow  dow[]  NOT NULL,
    mood mood[] NOT NULL
);

INSERT INTO enum_arrays
VALUES ('{Sun, NULL, Thu}', '{ok, NULL, ok}')
     , ('{Mon, Tue, Wed}', '{sad, NULL, happy}')
;

-- Execute round-trip to all supported formats. Protobuf has no null in a
-- repeated field, so the arrays carrying one come back short.
CREATE TABLE enum_arrays2 (LIKE enum_arrays INCLUDING ALL);
\set from_table enum_arrays
\set to_table enum_arrays2
\i test/utils/round-trip-formats.sql
\set ECHO errors
\! rm -rf /tmp/enums.tmp 2> /dev/null || true
