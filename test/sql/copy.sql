LOAD 'chdb';

CREATE TABLE logs (
    req_id    BIGINT PRIMARY KEY,
    name      TEXT     NOT NULL,
    path      TEXT     NOT NULL
);

INSERT INTO logs
VALUES (1, 'page_view',   '/users/profile')
     , (2, 'Page_View',   '/users/settings')
     , (3, 'PAGE_VIEW',   '/admin/dashboard')
     , (4, 'add_to_cart', '/products/shoes')
    --    (5, 'Add_To_Cart', '/products/hats'),
    --    (6, 'purchase',    '/checkout'),
    --    (7, 'PURCHASE',    '/checkout/confirm'),
    --    (8, 'share',       '/social/twitter'),
    --    (9, 'logout',      '/auth/logout'),
    --    (10, 'signup',     '/auth/signup')
;

-- COPY without URL should just work.
COPY logs TO STDOUT;

-- Should intercept known URLs schemas.
COPY logs TO 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv';
COPY logs TO 'http://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';
COPY logs TO 'https://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';
COPY logs TO 'gcs://storage.googleapis.com/clickhouse_public_datasets/my-test-bucket-768/data.csv.gz';
COPY logs TO 'az://account.blob.core.windows.net/container/path/to.csv';

COPY logs FROM 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv';
COPY logs FROM 'http://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';
COPY logs FROM 'https://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';
COPY logs FROM 'gcs://storage.googleapis.com/clickhouse_public_datasets/my-test-bucket-768/data.csv.gz';
COPY logs FROM 'az://account.blob.core.windows.net/container/path/to.csv';

COPY logs FROM 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv' (
    access_key 'key',
    access_secret 'secret',
    session_token 'big fat token',
    format 'parquet',
    structure 'id Int64',
    compression 'lz4',
    timeout 50000
);

COPY logs TO 'gcs://storage.googleapis.com/clickhouse_public_datasets/my-test-bucket-768/data.csv.gz' (
    ACCESS_KEY 'gcs_key',
    ACCESS_SECRET 'gcs_secret',
    STRUCTURE 'id UInt64',
    compression 'snappy'
);

COPY logs TO 'az://account.blob.core.windows.net/container/path/to.csv' (
    ACCESS_KEY 'az_key',
    ACCESS_SECRET 'az_secret',
    STRUCTURE 'id UInt64',
    compression 'snappy',
    format 'CSV',
    timeout 1000
);

COPY logs TO 'gcs://storage.googleapis.com/clickhouse_public_datasets/my-test-bucket-768/data.csv.gz' (
    ACCESS_KEY 'gcs_key',
    ACCESS_SECRET 'gcs_secret',
    STRUCTURE 'id UInt64'
);

COPY logs FROM 'https://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv' (
    FORMAT 'CSV',
    STRUCTURE 'id UInt32, num UInt32, age UInt32'
);

COPY logs FROM 'https://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv' (
    STRUCTURE 'id UInt32, num UInt32, age UInt32'
);
CREATE SCHEMA "big deal";

CREATE TABLE "big deal"."myParts" (
    part_id   BIGINT PRIMARY KEY,
    name      TEXT     NOT NULL
);

COPY "big deal"."myParts" FROM 'https://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';

-- Option failure modes.
COPY logs FROM 's3://thing.csv' (timeout '10');
COPY logs FROM 's3://thing.csv' (format 22, nope true);
COPY logs FROM 's3://thing.csv' (nonesuch 'hi');
