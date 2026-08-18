-- https://clickhouse.com/docs/get-started/sample-datasets/noaa

DROP TABLE IF EXISTS noaa;
DROP TYPE IF EXISTS weather_type;
CREATE TYPE weather_type AS ENUM ('', 'Normal', 'Fog', 'Heavy Fog', 'Thunder', 'Small Hail', 'Hail', 'Glaze', 'Dust/Ash', 'Smoke/Haze', 'Blowing/Drifting Snow', 'Tornado', 'High Winds', 'Blowing Spray', 'Mist', 'Drizzle', 'Freezing Drizzle', 'Rain', 'Freezing Rain', 'Snow', 'Unknown Precipitation', 'Ground Fog', 'Freezing Fog');

CREATE TABLE noaa (
   station_id         TEXT         NOT NULL,
   date               DATE         NOT NULL,
   tmp_avg            INTEGER      NOT NULL,
   temp_max           INTEGER      NOT NULL,
   temp_min           INTEGER      NOT NULL,
   precipitation      BIGINT       NOT NULL,
   snowfall           BIGINT       NOT NULL,
   snow_depth         BIGINT       NOT NULL,
   percent_daily_sun  SMALLINT     NOT NULL,
   average_wind_speed BIGINT       NOT NULL,
   max_wind_speed     BIGINT       NOT NULL,
   weather_type       weather_type NOT NULL,
   location           POINT        NOT NULL,
   elevation          FLOAT4       NOT NULL,
   name               TEXT         NOT NULL
);

LOAD 'chdb_hook';
\timing on
COPY noaa FROM 's3://datasets-documentation/noaa/noaa_enriched.parquet';
