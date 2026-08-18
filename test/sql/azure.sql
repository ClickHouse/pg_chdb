\set ECHO errors
-- Get Azure credentials from the environment.
\set access_key ''
\set access_secret ''
\getenv access_key AZURE_STORAGE_ACCOUNT
\getenv access_secret AZURE_STORAGE_ACCESS_KEY
SELECT :'access_key' = '' OR :'access_secret' = '' AS no_creds \gset

-- Bail if no credentials.
\if :no_creds
\echo 'SKIP: No Azure credentials found in the environment'
\quit
\endif
\set ECHO all

LOAD 'chdb_hook';

-- Create some random data to copy.
CREATE TABLE abs_things (
    id       INT  PRIMARY KEY,
    name     TEXT NOT NULL,
    quantity INT NOT NULL
);

INSERT INTO abs_things
SELECT id, format('thing-%s', (random() * 100)::int), (random() * 1000)::int FROM generate_series(1, 3) AS id;

-- Copy to existing file to ensure s3_truncate_on_insert is true.
COPY abs_things TO 'az://clickgres.blob.core.windows.net/pg-chdb-ci/keep-me.tsv' (
    access_key :'access_key',
    access_secret :'access_secret'
);

\set ECHO errors
-- Create unique URL path to avoid conflicts between concurrent execution.
SELECT (random() * 100000)::int AS rand \gset
\set arch ''
\getenv arch RUNNER_ARCH
\set url az://clickgres.blob.core.windows.net/pg-chdb-ci/ci/pg-:SERVER_VERSION_NUM - :arch - :rand /test.csv
\set ECHO all

-- Copy the data to Azure.
COPY abs_things TO :'url' (
    access_key :'access_key',
    access_secret :'access_secret'
);

-- Copy it back.
CREATE TABLE abs_things2 (LIKE abs_things INCLUDING ALL);
COPY abs_things2 FROM :'url' (
    access_key :'access_key',
    access_secret :'access_secret'
);

-- Make sure they're the same.
WITH x AS (
    SELECT * FROM abs_things EXCEPT ALL SELECT * FROM abs_things2
) SELECT COUNT(*) = 0 AS same FROM x \gset

\set ECHO errors
\if :same
\echo 'Table contents the same'
\else
\echo 'Table contents differ; want:'
SELECT * FROM abs_things;
\echo 'But got'
SELECT * FROM abs_things2;
\endif
