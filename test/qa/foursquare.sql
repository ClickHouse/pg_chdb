-- https://clickhouse.com/docs/get-started/sample-datasets/foursquare-os-places

DROP TABLE IF EXISTS foursquare;
CREATE TABLE foursquare (
    fsq_place_id        TEXT NOT NULL,
    name                TEXT NOT NULL,
    latitude            FLOAT8 NOT NULL,
    longitude           FLOAT8 NOT NULL,
    address             TEXT NOT NULL,
    locality            TEXT NOT NULL,
    region              TEXT NOT NULL,
    postcode            TEXT NOT NULL,
    admin_region        TEXT NOT NULL,
    post_town           TEXT NOT NULL,
    po_box              TEXT NOT NULL,
    country             TEXT NOT NULL,
    date_created        DATE NOT NULL,
    date_refreshed      DATE NOT NULL,
    date_closed         DATE NOT NULL,
    tel                 TEXT NOT NULL,
    website             TEXT NOT NULL,
    email               TEXT NOT NULL,
    facebook_id         TEXT NOT NULL,
    instagram           TEXT NOT NULL,
    twitter             TEXT NOT NULL,
    fsq_category_ids    TEXT[],
    fsq_category_labels TEXT[],
    placemaker_url      TEXT NOT NULL,
    geom                TEXT NOT NULL,
    bbox                FLOAT8[]
);

LOAD 'chdb';
\timing on
-- XXX files currently missing, will copy zero rows.
COPY foursquare FROM 's3://fsq-os-places-us-east-1/release/dt=2025-04-08/places/parquet/*' (
    format 'parquet'
);
