LOAD 'chdb';

/****************************************************************************/
-- PostgreSQL applies column type modifiers when importing values from chDB.

-- Copy the corpus to /tmp, where the server definitely has read access.
\! cp -f test/corpus/readings.csv /tmp/chdb-readings.csv
\set readings_csv file:///tmp/chdb-readings.csv
\set readings_structure 'value Decimal(10, 4), sensor String, taken DateTime64(6, ''UTC''), samples Array(Decimal(10, 4)), seq Int64, logged DateTime(''UTC'')'

SET TimeZone = 'UTC';

CREATE TABLE readings (
    value   NUMERIC(4, 1),   -- rounds
    sensor  CHAR(3),         -- pads
    taken   TIMESTAMP(3),    -- drops precision
    samples NUMERIC(4, 1)[], -- rounds every element
    seq     TEXT,            -- renders through the output function
    logged  TIME
);
COPY readings FROM :'readings_csv' (structure :'readings_structure');
SELECT * FROM readings;

-- DateTime to time doesn't skew with TimeZone
SET TimeZone = 'America/Los_Angeles';
TRUNCATE readings;
COPY readings FROM :'readings_csv' (structure :'readings_structure');
SELECT logged FROM readings;

\set ECHO errors
\set ci ''
\getenv ci CI
SELECT :'ci' = '' AS not_ci \gset
\if :not_ci
\! rm -f /tmp/chdb-readings.csv
\endif
