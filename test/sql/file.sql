LOAD 'chdb';

CREATE TABLE requests (
    req_id    BIGINT PRIMARY KEY,
    name      TEXT     NOT NULL,
    path      TEXT     NOT NULL
);

-- directory paths are passed to us in environment variables
\getenv test_dir PG_ABS_SRCDIR
\set file_base file:// :test_dir /corpus

\set requests_csv :file_base /requests.csv
COPY requests FROM :'requests_csv';
SELECT * FROM requests ORDER BY req_id;

\set temp_base file:// :test_dir /temp
\set dest :temp_base /requests.csv
COPY requests TO :'dest' (structure 'id UInt64, name String, path String');

\! cat test/temp/requests.csv
\! rm -rf test/temp
