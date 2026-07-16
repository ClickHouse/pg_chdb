LOAD 'chdb';

CREATE TABLE s3_times (
    id    INT PRIMARY KEY,
    months INT NOT NULL,
    days   INT NOT NULL
);

COPY s3_times FROM 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv';
SELECT * FROM s3_times ORDER BY id;
TRUNCATE s3_times;

COPY s3_times FROM 'http://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv';
SELECT * FROM s3_times ORDER BY id;
TRUNCATE s3_times;
