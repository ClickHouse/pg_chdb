LOAD 'chdb_hook';

-- Show COPY row counts and render NULL values explicitly
\pset null '#null#'
\set QUIET false

-- Copy corpus to consistent absolute path
\! cp -rf test/corpus /tmp/chdb-create
\set file_base file:///tmp/chdb-create
\set temp_base file:///tmp/create.tmp
\set requests_csv :file_base /requests.csv

/****************************************************************************/
-- Infer column names and types from CSV without schema
CREATE TABLE from_csv () WITH (structure_from = :'requests_csv');
SELECT attname, format_type(atttypid, atttypmod) AS type, attnotnull
  FROM pg_attribute WHERE attrelid = 'from_csv'::regclass AND attnum > 0
 ORDER BY attnum;
SELECT count(*) FROM from_csv;

/****************************************************************************/
-- Use explicit structure and preserve PostgreSQL storage options
CREATE TABLE named_csv () WITH (
    structure_from = :'requests_csv',
    format         = 'CSV',
    structure      = 'req_id UInt32, name String, path Nullable(String)',
    fillfactor     = 90
);
SELECT attname, format_type(atttypid, atttypmod) AS type, attnotnull
  FROM pg_attribute WHERE attrelid = 'named_csv'::regclass AND attnum > 0
 ORDER BY attnum;
SELECT reloptions FROM pg_class WHERE relname = 'named_csv';

/****************************************************************************/
-- Infer type modifiers from the leaf below every Array layer
CREATE TABLE arrayed () WITH (
    structure_from = :'requests_csv',
    format         = 'CSV',
    structure      = $$nums Array(Decimal(12,6)),
                       nested Array(Array(Decimal(9,4))),
                       stamps Array(Nullable(DateTime64(3))),
                       fixed Nullable(FixedString(4))$$
);
SELECT attname, format_type(atttypid, atttypmod) AS type, attndims, attnotnull
  FROM pg_attribute WHERE attrelid = 'arrayed'::regclass AND attnum > 0
 ORDER BY attnum;

/****************************************************************************/
-- Derive the fields of a Tuple and the pairs of a Map as text items
CREATE TABLE spread () WITH (
    structure_from = :'requests_csv',
    format         = 'CSV',
    structure      = $$req_id UInt32, t Tuple(a String, b UInt8),
                       m Map(String, UInt8), at Array(Tuple(UInt8, UInt8))$$
);
SELECT attname, format_type(atttypid, atttypmod) AS type, attndims, attnotnull
  FROM pg_attribute WHERE attrelid = 'spread'::regclass AND attnum > 0
 ORDER BY attnum;

/****************************************************************************/
-- Keep the case ClickHouse reports and quote names that need it
-- chDB unescapes a parameter once, so an escape inside a name needs doubling
CREATE TABLE quoted () WITH (
    copy_from = :'requests_csv',
    format    = 'CSV',
    structure = 'ReqId UInt32, `odd name` String, `Mixed \\`Case\\\\` Nullable(String)'
);
SELECT attname, format_type(atttypid, atttypmod) AS type, attnotnull
  FROM pg_attribute WHERE attrelid = 'quoted'::regclass AND attnum > 0
 ORDER BY attnum;
SELECT * FROM quoted ORDER BY "ReqId";

/****************************************************************************/
-- Infer columns and copy rows
CREATE TABLE loaded_csv () WITH (copy_from = :'requests_csv');
SELECT * FROM loaded_csv ORDER BY c1;

-- Copy only rows when statement defines columns
CREATE TABLE given_csv (
    req_id BIGINT PRIMARY KEY,
    name   TEXT NOT NULL,
    path   TEXT NOT NULL
) WITH (copy_from = :'requests_csv');
SELECT * FROM given_csv ORDER BY req_id;

-- Copy rows into partition using columns from parent
CREATE TABLE parted (req_id BIGINT, name TEXT, path TEXT) PARTITION BY RANGE (req_id);
CREATE TABLE parted_low PARTITION OF parted FOR VALUES FROM (MINVALUE) TO (100)
    WITH (copy_from = :'requests_csv');
SELECT * FROM parted ORDER BY req_id;

/****************************************************************************/
-- Preserve columns and types across COPY TO and CREATE TABLE
CREATE TABLE typed (
    i2  INT2        NOT NULL,
    i4  INT4            NULL,
    i8  INT8            NULL,
    num NUMERIC(12,6)   NULL,
    f4  FLOAT4      NOT NULL,
    f8  FLOAT8          NULL,
    b   BOOL        NOT NULL,
    t   TEXT        NOT NULL,
    d   DATE        NOT NULL,
    ts  TIMESTAMPTZ NOT NULL,
    u   UUID        NOT NULL,
    arr INT4[]      NOT NULL
);
INSERT INTO typed
VALUES (1, 2, 3, 4.567890, 8.5, 9.25, true, 'hi', '2026-08-19',
        '2026-08-19 12:34:56.123456+00', '3f333df6-90a4-4fda-8dd3-9485d27cee36',
        '{1,2,3}')
     , (-1, NULL, NULL, NULL, -8.5, NULL, false, 'bye', '1999-12-31',
        '1999-12-31 23:59:59+00', '00000000-0000-0000-0000-000000000000', '{}')
;

\set typed_out :temp_base /typed.parquet
COPY typed TO :'typed_out';

CREATE TABLE typed2 () WITH (copy_from = :'typed_out');
SELECT attname, format_type(atttypid, atttypmod) AS type, attnotnull
  FROM pg_attribute WHERE attrelid = 'typed2'::regclass AND attnum > 0
 ORDER BY attnum;
SELECT * FROM typed2 ORDER BY i2;

/****************************************************************************/
-- Reject explicit and inferred columns together
CREATE TABLE oops (id INT) WITH (structure_from = :'requests_csv');

-- Reject separate URLs for columns and rows
CREATE TABLE oops () WITH (structure_from = :'requests_csv', copy_from = :'requests_csv');

-- Reject URL schemes unsupported by chDB
CREATE TABLE oops () WITH (structure_from = 'ftp://example.com/requests.csv');

-- Reject existing relation regardless of IF NOT EXISTS
CREATE TABLE from_csv () WITH (structure_from = :'requests_csv');
CREATE TABLE IF NOT EXISTS from_csv () WITH (copy_from = :'requests_csv');

-- Reject ClickHouse types without PostgreSQL equivalents
CREATE TABLE oops () WITH (
    structure_from = :'requests_csv',
    structure      = 'req_id UInt32, big Int128'
);

-- Reject options unknown to chDB and PostgreSQL
CREATE TABLE oops () WITH (structure_from = :'requests_csv', nonesuch = 1);

\set ECHO errors
\! rm -rf /tmp/create.tmp 2> /dev/null || true
\! rm -rf /tmp/chdb-create 2> /dev/null || true
