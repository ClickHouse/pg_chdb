-- https://clickhouse.com/docs/get-started/sample-datasets/amazon-reviews

DROP TABLE IF EXISTS amazon_reviews;
CREATE TABLE amazon_reviews (
    review_date       DATE     NOT NULL,
    marketplace       TEXT     NOT NULL,
    customer_id       BIGINT   NOT NULL,
    review_id         TEXT     NOT NULL,
    product_id        TEXT     NOT NULL,
    product_parent    BIGINT   NOT NULL,
    product_title     TEXT     NOT NULL,
    product_category  TEXT     NOT NULL,
    star_rating       SMALLINT NOT NULL,
    helpful_votes     BIGINT   NOT NULL,
    total_votes       BIGINT   NOT NULL,
    vine              BOOL     NOT NULL,
    verified_purchase BOOL     NOT NULL,
    review_headline   TEXT     NOT NULL,
    review_body       TEXT     NOT NULL
);

LOAD 'chdb';
\timing on
COPY amazon_reviews FROM 's3://datasets-documentation/amazon_reviews/amazon_reviews_2015.snappy.parquet';
