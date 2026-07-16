LOAD 'chdb';

CREATE TABLE gcs_times (
    id    INT PRIMARY KEY,
    months INT NOT NULL,
    days   INT NOT NULL
);

COPY gcs_times FROM 'gcs://storage.googleapis.com/clickhouse_public_datasets/my-test-bucket-768/data.csv.gz';
SELECT * FROM gcs_times ORDER BY id;
TRUNCATE gcs_times;
