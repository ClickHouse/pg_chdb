-- https://clickhouse.com/docs/get-started/quickstarts/tutorial

BEGIN;
SET client_min_messages TO WARNING;

CREATE TABLE IF NOT EXISTS target (
    trip_id                 bigint,
    vendor_id               bigint,
    pickup_date             date,
    pickup_datetime         timestamp with time zone,
    dropoff_date            date,
    dropoff_datetime        timestamp with time zone,
    store_and_fwd_flag      smallint,
    rate_code_id            smallint,
    pickup_longitude        double precision,
    pickup_latitude         double precision,
    dropoff_longitude       double precision,
    dropoff_latitude        double precision,
    passenger_count         smallint,
    trip_distance           double precision,
    fare_amount             numeric(10,2),
    extra                   numeric(10,2),
    mta_tax                 numeric(10,2),
    tip_amount              numeric(10,2),
    tolls_amount            numeric(10,2),
    ehail_fee               numeric(10,2),
    improvement_surcharge   numeric(10,2),
    total_amount            numeric(10,2),
    payment_type            text,
    trip_type               smallint,
    pickup                  character varying(25),
    dropoff                 character varying(25),
    cab_type                text,
    pickup_nyct2010_gid     smallint,
    pickup_ctlabel          double precision,
    pickup_borocode         smallint,
    pickup_ct2010           text,
    pickup_boroct2010       text,
    pickup_cdeligibil       text,
    pickup_ntacode          character varying(4),
    pickup_ntaname          text,
    pickup_puma             integer,
    dropoff_nyct2010_gid    smallint,
    dropoff_ctlabel         double precision,
    dropoff_borocode        smallint,
    dropoff_ct2010          text,
    dropoff_boroct2010      text,
    dropoff_cdeligibil      text,
    dropoff_ntacode         character varying(4),
    dropoff_ntaname         text,
    dropoff_puma            integer
);
  
\ir util.pgsql
\set base_url s3://chdb-lakedata-public/taxi_trips

/***************************************************************************/
-- CSV
\set url :base_url/taxi_trips.csv

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'taxi', 'CSV', 'none', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- CSV gzip
\set url :base_url/taxi_trips.csv.gz

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_csv(:'url', header => true) r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'taxi', 'CSV', 'gzip', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- JSON
\set url :base_url/taxi_trips.json

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'taxi', 'JSON', 'none', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- JSON gzip
\set url :base_url/taxi_trips.json.gz

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_json(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'taxi', 'JSON', 'gzip', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;

/***************************************************************************/
-- Parquet
\set url :base_url/taxi_trips.parquet

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_parquet(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing1 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_parquet(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing2 \gset

SELECT clock_timestamp() AS _start_ts \gset
INSERT INTO target SELECT :select_list FROM read_parquet(:'url') r;
SELECT clock_timestamp() AS _end_ts \gset
SELECT round(1000 * (extract(epoch FROM :'_end_ts'::timestamptz - :'_start_ts'::timestamptz)) - (:_overhead*3), 4) AS _timing3 \gset

SELECT round(avg(y), 4) AS _avg FROM (VALUES(:_timing1), (:_timing2), (:_timing3)) AS x(y) \gset
COPY(SELECT 'pg_duckdb', 'taxi', 'Parquet', 'zstd', :_timing1, :_timing2, :_timing3, :_avg) TO STDOUT;


ROLLBACK;
