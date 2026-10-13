LOAD 'chdb_hook';

CREATE TABLE requests (
    req_id    BIGINT PRIMARY KEY,
    name      TEXT     NOT NULL,
    path      TEXT     NOT NULL
);

-- Disable quiet to emit COPY numbers and make NULLs show up
\pset null '#null#'
\set QUIET false

-- Set up paths we'll use.
\! cp -rf test/corpus /tmp/chdb-corpus
\set file_base file:///tmp/chdb-corpus
\set temp_base file:///tmp/file.tmp

\set requests_csv :file_base /requests.csv
COPY requests FROM :'requests_csv';
SELECT * FROM requests ORDER BY req_id;

\set requests_out :temp_base /requests.csv
COPY requests TO :'requests_out' (structure 'id UInt64, name String, path String');

TRUNCATE requests;
COPY requests FROM :'requests_out';
SELECT * FROM requests ORDER BY req_id;

-- PostgreSQL COPY aliases become per-query ClickHouse format settings.
\set delimited_out :temp_base /delimited.csv
COPY requests TO :'delimited_out' (format 'CSV', delimiter '|');
TRUNCATE requests;
COPY requests FROM :'delimited_out' (format 'CSV', delimiter '|');
SELECT * FROM requests ORDER BY req_id \g (format=csv)

-- Format settings apply only to the operation that specifies them.
\set isolated_delimited_out :temp_base /isolated-delimited.csv
\set isolated_default_out :temp_base /isolated-default.csv
COPY requests TO :'isolated_delimited_out' (format 'CSV', delimiter '|');
COPY requests TO :'isolated_default_out' (format 'CSV');
COPY (
    SELECT split_part(
        pg_read_file('/tmp/file.tmp/isolated-delimited.csv'), E'\n', 1
    )
) TO STDOUT;
COPY (
    SELECT split_part(
        pg_read_file('/tmp/file.tmp/isolated-default.csv'), E'\n', 1
    )
) TO STDOUT;

-- Test importing from ClickHouse with all possible backslash escapes.
-- https://clickhouse.com/docs/interfaces/formats/TabSeparated
CREATE TABLE people (
    id           INT PRIMARY KEY,
    family_name  TEXT NOT NULL,
    given_name   TEXT NOT NULL,
    notes        TEXT     NULL
);

\set people_tsv :file_base /people.tsv
COPY people FROM :'people_tsv';
SELECT * FROM people ORDER BY id;

-- Export back out.
\set people_out :temp_base /people.tsv
COPY people TO :'people_out' (structure 'i Int32, f String, g String, n Nullable(String)');

-- Import it again;
TRUNCATE people;
COPY people FROM :'people_out';
SELECT * FROM people ORDER BY id;

-- Export it again, should replace previous.
COPY people TO :'people_out' (structure 'i Int32, f String, g String, n Nullable(String)');
TRUNCATE people;
COPY people FROM :'people_out';
SELECT * FROM people ORDER BY id;

-- Should fail to load record with invalid byte.
TRUNCATE people;
\set people_tsv :file_base /invalid-people.tsv
COPY people FROM :'people_tsv';

-- Have the COPY replace the characters.
COPY people FROM :'people_tsv' (encoding_check 'replace');
SELECT family_name FROM people ORDER BY id;

-- Have the COPY remove the characters.
TRUNCATE people;
COPY people FROM :'people_tsv' (encoding_check 'remove');
SELECT family_name FROM people ORDER BY id;

-- Have the COPY truncate the characters.
TRUNCATE people;
COPY people FROM :'people_tsv' (encoding_check 'Truncate');
SELECT family_name FROM people ORDER BY id;

-- Back to fail.
COPY people FROM :'people_tsv' (encoding_check 'FAIL');

\set ECHO errors
\! rm -rf /tmp/file.tmp 2> /dev/null || true
\! rm -rf /tmp/chdb-corpus 2> /dev/null || true
