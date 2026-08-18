-- https://clickhouse.com/docs/get-started/sample-datasets/brown-benchmark

DROP TABLE IF EXISTS mgbench_logs1;
CREATE TABLE mgbench_logs1 (
    log_time      TIMESTAMPTZ NOT NULL,
    machine_name  TEXT        NOT NULL,
    machine_group TEXT        NOT NULL,
    cpu_idle      FLOAT4          NULL,
    cpu_nice      FLOAT4          NULL,
    cpu_system    FLOAT4          NULL,
    cpu_user      FLOAT4          NULL,
    cpu_wio       FLOAT4          NULL,
    disk_free     FLOAT4          NULL,
    disk_total    FLOAT4          NULL,
    part_max_used FLOAT4          NULL,
    load_fifteen  FLOAT4          NULL,
    load_five     FLOAT4          NULL,
    load_one      FLOAT4          NULL,
    mem_buffers   FLOAT4          NULL,
    mem_cached    FLOAT4          NULL,
    mem_free      FLOAT4          NULL,
    mem_shared    FLOAT4          NULL,
    swap_free     FLOAT4          NULL,
    bytes_in      FLOAT4          NULL,
    bytes_out     FLOAT4          NULL
);

DROP TABLE IF EXISTS mgbench_logs2;
CREATE TABLE mgbench_logs2 (
    log_time    TIMESTAMPTZ NOT NULL,
    client_ip   INET        NOT NULL,
    request     TEXT        NOT NULL,
    status_code INTEGER     NOT NULL,
    object_size BIGINT      NOT NULL
);

DROP TABLE IF EXISTS mgbench_logs3;
CREATE TABLE mgbench_logs3 (
  log_time     TIMESTAMPTZ   NOT NULL,
  device_id    CHARACTER(15) NOT NULL,
  device_name  TEXT          NOT NULL,
  device_type  TEXT          NOT NULL,
  device_floor SMALLINT      NOT NULL,
  event_type   TEXT          NOT NULL,
  event_unit   CHARACTER(1)  NOT NULL,
  event_value  FLOAT4            NULL
);

LOAD 'chdb_hook';
\timing on
COPY mgbench_logs1 FROM 'https://datasets.clickhouse.com/mgbench1.csv.xz' ( format 'CSVWithNames');
COPY mgbench_logs2 FROM 'https://datasets.clickhouse.com/mgbench2.csv.xz' ( format 'CSVWithNames');
COPY mgbench_logs3 FROM 'https://datasets.clickhouse.com/mgbench3.csv.xz' ( format 'CSVWithNames');
