SET client_min_messages TO WARNING;
SET datestyle TO ISO;
SET timezone TO UTC;
\getenv workdir WORKDIR
\set file_base file:// :workdir

LOAD 'chdb_hook';

-- https://clickhouse.com/docs/get-started/quickstarts/tutorial

CREATE TABLE IF NOT EXISTS taxi_trips (
    trip_id                 bigint                    NOT NULL,
    vendor_id               bigint                    NOT NULL,
    pickup_date             date                      NOT NULL,
    pickup_datetime         timestamp with time zone  NOT NULL,
    dropoff_date            date                      NOT NULL,
    dropoff_datetime        timestamp with time zone  NOT NULL,
    store_and_fwd_flag      smallint                  NOT NULL,
    rate_code_id            smallint                  NOT NULL,
    pickup_longitude        double precision          NOT NULL,
    pickup_latitude         double precision          NOT NULL,
    dropoff_longitude       double precision          NOT NULL,
    dropoff_latitude        double precision          NOT NULL,
    passenger_count         smallint                  NOT NULL,
    trip_distance           double precision          NOT NULL,
    fare_amount             numeric(10,2)             NOT NULL,
    extra                   numeric(10,2)             NOT NULL,
    mta_tax                 numeric(10,2)             NOT NULL,
    tip_amount              numeric(10,2)             NOT NULL,
    tolls_amount            numeric(10,2)             NOT NULL,
    ehail_fee               numeric(10,2)             NOT NULL,
    improvement_surcharge   numeric(10,2)             NOT NULL,
    total_amount            numeric(10,2)             NOT NULL,
    payment_type            text                      NOT NULL,
    trip_type               smallint                  NOT NULL,
    pickup                  character varying(25)     NOT NULL,
    dropoff                 character varying(25)     NOT NULL,
    cab_type                text                      NOT NULL,
    pickup_nyct2010_gid     smallint                  NOT NULL,
    pickup_ctlabel          double precision          NOT NULL,
    pickup_borocode         smallint                  NOT NULL,
    pickup_ct2010           text                      NOT NULL,
    pickup_boroct2010       text                      NOT NULL,
    pickup_cdeligibil       text                      NOT NULL,
    pickup_ntacode          character varying(4)      NOT NULL,
    pickup_ntaname          text                      NOT NULL,
    pickup_puma             integer                   NOT NULL,
    dropoff_nyct2010_gid    smallint                  NOT NULL,
    dropoff_ctlabel         double precision          NOT NULL,
    dropoff_borocode        smallint                  NOT NULL,
    dropoff_ct2010          text                      NOT NULL,
    dropoff_boroct2010      text                      NOT NULL,
    dropoff_cdeligibil      text                      NOT NULL,
    dropoff_ntacode         character varying(4)      NOT NULL,
    dropoff_ntaname         text                      NOT NULL,
    dropoff_puma            integer                   NOT NULL
);

-- Insert the records if they're not present.
SELECT NOT EXISTS (SELECT 1 FROM taxi_trips LIMIT 1) AS is_empty \gset
\if :is_empty
    \echo Loading trips_1.gz
    \set orig_file :file_base /trips_1.gz
    COPY taxi_trips FROM :'orig_file' (format 'TabSeparatedWithNames');
\endif

\set structure 'trip_id Int64, vendor_id Int64, pickup_date Date, pickup_datetime DateTime, dropoff_date Date, dropoff_datetime DateTime, store_and_fwd_flag Int8, rate_code_id Int8, pickup_longitude Float64, pickup_latitude Float64, dropoff_longitude Float64, dropoff_latitude Float64, passenger_count Int8, trip_distance Float64, fare_amount Decimal(10,2), extra Decimal(10,2), mta_tax Decimal(10,2), tip_amount Decimal(10,2), tolls_amount Decimal(10,2), ehail_fee Decimal(10,2), improvement_surcharge Decimal(10,2), total_amount Decimal(10,2), payment_type String, trip_type Int8, pickup String, dropoff String, cab_type String, pickup_nyct2010_gid Int8, pickup_ctlabel Float64, pickup_borocode Int8, pickup_ct2010 String, pickup_boroct2010 String, pickup_cdeligibil String, pickup_ntacode String, pickup_ntaname String, pickup_puma Int32, dropoff_nyct2010_gid Int8, dropoff_ctlabel Float64, dropoff_borocode Int8, dropoff_ct2010 String, dropoff_boroct2010 String, dropoff_cdeligibil String, dropoff_ntacode String, dropoff_ntaname String, dropoff_puma Int32'

\if `[ ! -f taxi_trips.tsv ] && echo 1 || echo 0`
    \echo Exporting to taxi_trips.tsv
    \set tsv_file :file_base /taxi_trips.tsv
    COPY taxi_trips TO :'tsv_file' ( format 'TabSeparatedWithNames', structure :'structure');
    \! gzip -fk taxi_trips.tsv
\endif

\if `[ ! -f taxi_trips.csv ] && echo 1 || echo 0`
    \echo Exporting to taxi_trips.csv
    \set csv_file :file_base /taxi_trips.csv
    COPY taxi_trips TO :'csv_file' ( format 'CSVWithNames', structure :'structure');
    \! gzip -fk taxi_trips.csv
\endif

\if `[ ! -f taxi_trips.json ] && echo 1 || echo 0`
    \echo Exporting to taxi_trips.json
    \set json_file :file_base /taxi_trips.json
    COPY taxi_trips TO :'json_file' ( format 'JSONEachRow', structure :'structure');
    \! gzip -fk taxi_trips.json
\endif

\if `[ ! -f taxi_trips.parquet ] && echo 1 || echo 0`
    \echo Exporting to taxi_trips.parquet
    \set parquet_file :file_base /taxi_trips.parquet
    COPY taxi_trips TO :'parquet_file' ( format 'parquet', structure :'structure');
\endif

\if `[ ! -f taxi_trips.arrow ] && echo 1 || echo 0`
    \echo Exporting to taxi_trips.arrow
    \set arrow_file :file_base /taxi_trips.arrow
    COPY taxi_trips TO :'arrow_file' ( format 'arrow', structure :'structure');
\endif

\if `[ ! -f taxi_trips.avro ] && echo 1 || echo 0`
    \echo Exporting to taxi_trips.avro
    \set avro_file :file_base /taxi_trips.avro
    COPY taxi_trips TO :'avro_file' ( format 'avro', structure :'structure');
\endif
