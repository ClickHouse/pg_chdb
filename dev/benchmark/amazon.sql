SET client_min_messages TO WARNING;
SET datestyle TO ISO;
SET timezone TO UTC;
\getenv workdir WORKDIR
\set file_base file:// :workdir

LOAD 'chdb_hook';

-- https://clickhouse.com/docs/get-started/sample-datasets/amazon-reviews

CREATE TABLE IF NOT EXISTS amazon_reviews (
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

-- Insert the records if they're not present.
SELECT NOT EXISTS (SELECT 1 FROM amazon_reviews LIMIT 1) AS is_empty \gset
\if :is_empty
    \echo Loading amazon_reviews_2015.snappy.parquet
    \set orig_file :file_base /amazon_reviews_2015.snappy.parquet
    COPY amazon_reviews FROM :'orig_file';
\endif

\set structure 'review_date Date32, marketplace String, customer_id UInt64, review_id String, product_id String, product_parent UInt64, product_title String, product_category String, star_rating UInt8, helpful_votes UInt32, total_votes UInt32, vine Bool, verified_purchase Bool, review_headline String, review_body String'

\if `[ ! -f amazon_reviews_2015.tsv ] && echo 1 || echo 0`
    \echo Exporting to amazon_reviews_2015.tsv
    \set tsv_file :file_base /amazon_reviews_2015.tsv
    COPY amazon_reviews TO :'tsv_file' ( format 'TabSeparatedWithNames', structure :'structure');
    \! gzip -fk amazon_reviews_2015.tsv
\endif

\if `[ ! -f amazon_reviews_2015.csv ] && echo 1 || echo 0`
    \echo Exporting to amazon_reviews_2015.csv
    \set csv_file :file_base /amazon_reviews_2015.csv
    COPY amazon_reviews TO :'csv_file' ( format 'CSVWithNames', structure :'structure');
    \! gzip -fk amazon_reviews_2015.csv
\endif

\if `[ ! -f amazon_reviews_2015.json ] && echo 1 || echo 0`
    \echo Exporting to amazon_reviews_2015.json
    \set json_file :file_base /amazon_reviews_2015.json
    COPY amazon_reviews TO :'json_file' ( format 'JSONEachRow', structure :'structure');
    \! gzip -fk amazon_reviews_2015.json
\endif

\if `[ ! -f amazon_reviews_2015.parquet ] && echo 1 || echo 0`
    \echo Exporting to amazon_reviews_2015.parquet
    \set parquet_file :file_base /amazon_reviews_2015.parquet
    COPY amazon_reviews TO :'parquet_file' ( format 'parquet', structure :'structure');
\endif

\if `[ ! -f amazon_reviews_2015.arrow ] && echo 1 || echo 0`
    \echo Exporting to amazon_reviews_2015.arrow
    \set arrow_file :file_base /amazon_reviews_2015.arrow
    COPY amazon_reviews TO :'arrow_file' ( format 'arrow', structure :'structure');
\endif

\if `[ ! -f amazon_reviews_2015.avro ] && echo 1 || echo 0`
    \echo Exporting to amazon_reviews_2015.avro
    \set avro_file :file_base /amazon_reviews_2015.avro
    COPY amazon_reviews TO :'avro_file' ( format 'avro', structure :'structure');
\endif
