\set ECHO errors
-- Get base URL from the environment.
\set base_url ''
\getenv base_url PG_CHDB_HTTP_URL
SELECT :'base_url' = '' AS no_url \gset

-- Bail if no URL.
\if :no_url
\echo 'SKIP: No URL found in $PG_CHDB_HTTP_URL'
\quit
\endif

-- Create unique URL path to avoid conflicts between concurrent execution.
SELECT (random() * 100000)::int AS rand \gset
\set arch ''
\getenv arch RUNNER_ARCH
\set url :base_url /ci/:SERVER_VERSION_NUM - :arch - :rand /test.csv
\set ECHO all

LOAD 'chdb_hook';

-- Create some random data to copy.
CREATE TABLE url_things (
    id       INT  PRIMARY KEY,
    name     TEXT NOT NULL,
    quantity INT NOT NULL
);

INSERT INTO url_things
SELECT id, format('thing-%s', (random() * 100)::int), (random() * 1000)::int FROM generate_series(1, 3) AS id;

-- Copy the data to S3.
COPY url_things TO :'url';

-- Second copy should not fail.
COPY url_things TO :'url';

-- Copy it back.
CREATE TABLE url_things2 (LIKE url_things INCLUDING ALL);
COPY url_things2 FROM :'url';

-- Make sure they're the same.
WITH x AS (
    SELECT * FROM url_things EXCEPT ALL SELECT * FROM url_things2
) SELECT COUNT(*) = 0 AS same FROM x \gset

\set ECHO errors
\if :same
\echo 'Table contents the same'
\else
\echo 'Table contents differ; want:'
SELECT * FROM url_things;
\echo 'But got'
SELECT * FROM url_things2;
\endif
