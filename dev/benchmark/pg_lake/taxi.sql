-- https://clickhouse.com/docs/get-started/quickstarts/tutorial

BEGIN;
SET client_min_messages TO WARNING;

-- Table name `target` required by util.pgsql/load_target().
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

COPY (SELECT * FROM load_target('taxi', 'CSV', 'none', 'taxi_trips/taxi_trips.csv')) TO STDOUT;
COPY (SELECT * FROM load_target('taxi', 'CSV', 'gzip', 'taxi_trips/taxi_trips.csv.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('taxi', 'JSON', 'none', 'taxi_trips/taxi_trips.json')) TO STDOUT;
COPY (SELECT * FROM load_target('taxi', 'JSON', 'gzip', 'taxi_trips/taxi_trips.json.gz')) TO STDOUT;
COPY (SELECT * FROM load_target('taxi', 'Parquet', 'zstd', 'taxi_trips/taxi_trips.parquet')) TO STDOUT;

ROLLBACK;
