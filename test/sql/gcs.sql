LOAD 'chdb';

-- Simple COPY FROM without credentials.
CREATE TABLE gcs_times (
    id    INT PRIMARY KEY,
    months INT NOT NULL,
    days   INT NOT NULL
);

COPY gcs_times FROM 'gcs://storage.googleapis.com/clickhouse_public_datasets/my-test-bucket-768/data.csv.gz';
SELECT * FROM gcs_times ORDER BY id;

\set ECHO errors
-- Get GCP credentials from the environment.
\set access_key ''
\set access_secret ''
\getenv access_key CLOUDSDK_AUTH_HMAC_KEY
\getenv access_secret CLOUDSDK_AUTH_HMAC_SECRET
SELECT :'access_key' = '' OR :'access_secret' = '' AS no_creds \gset

-- Bail if no credentials.
\if :no_creds
\echo 'SKIP: No GCP credentials found in the environment'
\quit
\endif
\set ECHO all

-- Create some random data to copy.
CREATE TABLE gcs_things (
    id       INT  PRIMARY KEY,
    name     TEXT NOT NULL,
    quantity INT NOT NULL
);

INSERT INTO gcs_things
VALUES ((random() * 10000)::int, format('thing-%s', (random() * 100)::int), (random() * 1000)::int)
     , ((random() * 10000)::int, format('thing-%s', (random() * 100)::int), (random() * 1000)::int)
     , ((random() * 10000)::int, format('thing-%s', (random() * 100)::int), (random() * 1000)::int)
;

-- Copy to existing file to ensure s3_truncate_on_insert is true.
COPY gcs_things TO 'gs://storage.googleapis.com/pg-chdb-ci/keep-me.tsv' (
    access_key :'access_key',
    access_secret :'access_secret'
);

\set ECHO errors
-- Create unique URL path to avoid conflicts between concurrent execution.
SELECT (random() * 100000)::int AS rand \gset
\set arch ''
\getenv arch RUNNER_ARCH
\set url gs://storage.googleapis.com/pg-chdb-ci/ci/:SERVER_VERSION_NUM - :arch - :rand /test.csv
\set ECHO all

-- Copy the data to GCS.
COPY gcs_things TO :'url' (
    access_key :'access_key',
    access_secret :'access_secret'
);

-- Copy it back.
CREATE TABLE gcs_things2 (LIKE gcs_things INCLUDING ALL);
COPY gcs_things2 FROM :'url' (
    access_key :'access_key',
    access_secret :'access_secret'
);

-- Make sure they're the same.
WITH x AS (
    SELECT * FROM gcs_things EXCEPT ALL SELECT * FROM gcs_things2
) SELECT COUNT(*) = 0 AS same FROM x \gset

\set ECHO errors
\if :same
\echo 'Table contents the same'
\else
\echo 'Table contents differ; want:'
SELECT * FROM gcs_things;
\echo 'But got'
SELECT * FROM gcs_things2;
\endif
