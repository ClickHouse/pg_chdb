-- https://clickhouse.com/docs/get-started/sample-datasets/cell-towers

DROP TABLE IF EXISTS cell_towers;
DROP TYPE frequency;
CREATE TYPE frequency AS ENUM ('', 'CDMA', 'GSM', 'LTE', 'NR', 'UMTS');

CREATE TABLE cell_towers (
    radio         frequency   NOT NULL,
    mcc           INTEGER     NOT NULL,
    net           INTEGER     NOT NULL,
    area          INTEGER     NOT NULL,
    cell          BIGINT      NOT NULL,
    unit          SMALLINT    NOT NULL,
    lon           FLOAT8      NOT NULL,
    lat           FLOAT8      NOT NULL,
    range         BIGINT      NOT NULL,
    samples       BIGINT      NOT NULL,
    changeable    SMALLINT    NOT NULL,
    created       TIMESTAMPTZ NOT NULL,
    updated       TIMESTAMPTZ NOT NULL,
    averageSignal SMALLINT    NOT NULL
);

LOAD 'chdb_hook';
\timing on
COPY cell_towers FROM 's3://datasets-documentation/cell_towers/cell_towers.csv.xz' (
    format 'CSVWithNames'
);
