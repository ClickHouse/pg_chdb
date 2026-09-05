-- https://clickhouse.com/docs/get-started/sample-datasets/amazon-reviews

BEGIN;
SET client_min_messages TO WARNING;

-- Table name `target` required by util.pgsql/load_target().
CREATE TABLE target (
    review_date       DATE,
    marketplace       TEXT,
    customer_id       BIGINT,
    review_id         TEXT,
    product_id        TEXT,
    product_parent    BIGINT,
    product_title     TEXT,
    product_category  TEXT,
    star_rating       SMALLINT,
    helpful_votes     BIGINT,
    total_votes       BIGINT,
    vine              BOOL,
    verified_purchase BOOL,
    review_headline   TEXT,
    review_body       TEXT
);

\ir util.pgsql

COPY (SELECT * FROM load_target('amazon', 'CSV', 'none', 'amazon/amazon_reviews_2015.csv')) TO STDOUT;
COPY (SELECT * FROM load_target('amazon', 'CSV', 'gzip', 'amazon/amazon_reviews_2015.csv.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('amazon', 'JSON', 'none', 'amazon/amazon_reviews_2015.json')) TO STDOUT;
COPY (SELECT * FROM load_target('amazon', 'JSON', 'gzip', 'amazon/amazon_reviews_2015.json.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('amazon', 'Parquet', 'zstd', 'amazon/amazon_reviews_2015.parquet')) TO STDOUT;

ROLLBACK;
