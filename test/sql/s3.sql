LOAD 'chdb_hook';

-- Simple COPY FROM without credentials.
CREATE TABLE s3_times (
    id    INT PRIMARY KEY,
    months INT NOT NULL,
    days   INT NOT NULL
);

-- Try S3 URI.
COPY s3_times FROM 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv';
SELECT * FROM s3_times ORDER BY id;

-- Try Object URL:
TRUNCATE s3_times;
COPY s3_times FROM 's3://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';
SELECT * FROM s3_times ORDER BY id;

\set ECHO errors
-- Get AWS credentials from the environment.
\set access_key ''
\set access_secret ''
\getenv access_key AWS_ACCESS_KEY_ID
\getenv access_secret AWS_SECRET_ACCESS_KEY
\getenv session_token AWS_SESSION_TOKEN
SELECT :'access_key' = '' OR :'access_secret' = '' AS no_creds \gset

-- Bail if no credentials.
\if :no_creds
\echo 'SKIP: No AWS credentials found in the environment'
\quit
\endif
\set ECHO all

-- Create some random data to copy.
CREATE TABLE s3_things (
    id       INT  PRIMARY KEY,
    name     TEXT NOT NULL,
    quantity INT NOT NULL
);

INSERT INTO s3_things
SELECT id, format('thing-%s', (random() * 100)::int), (random() * 1000)::int FROM generate_series(1, 3) AS id;

-- Copy to existing file to ensure s3_truncate_on_insert is true.
COPY s3_things TO 's3://pg-chdb-ci-248825820370-us-east-2-an/keep-me.tsv' (
    access_key :'access_key',
    access_secret :'access_secret',
    session_token :'session_token'
);

\set ECHO errors
-- Create unique URL path to avoid conflicts between concurrent execution.
SELECT (random() * 100000)::int AS rand \gset
\set arch ''
\getenv arch RUNNER_ARCH
\set url s3://pg-chdb-ci-248825820370-us-east-2-an/ci/:SERVER_VERSION_NUM - :arch - :rand /test.csv
\set ECHO all

-- Copy the data to S3.
COPY s3_things TO :'url' (
    access_key :'access_key',
    access_secret :'access_secret',
    session_token :'session_token'
);

-- Copy it back.
CREATE TABLE s3_things2 (LIKE s3_things INCLUDING ALL);
COPY s3_things2 FROM :'url' (
    access_key :'access_key',
    access_secret :'access_secret',
    session_token :'session_token'
);

-- Make sure they're the same.
WITH x AS (
    SELECT * FROM s3_things EXCEPT ALL SELECT * FROM s3_things2
) SELECT COUNT(*) = 0 AS same FROM x \gset

\set ECHO errors
\if :same
\echo 'Table contents the same'
\else
\echo 'Table contents differ; want:'
SELECT * FROM s3_things;
\echo 'But got'
SELECT * FROM s3_things2;
\endif
