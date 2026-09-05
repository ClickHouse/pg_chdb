BEGIN;
SET client_min_messages TO WARNING;

-- Determines the order of the result.
CREATE TYPE ext_name AS ENUM(
  'pg_lake', 'pg_duckdb', 'aws_s3', 'chdb_hook'
);

CREATE TABLE results (
    extension   ext_name,
    dataset     TEXT,
    format      TEXT,
    compression TEXT,
    run1        NUMERIC,
    run2        NUMERIC,
    run3        NUMERIC,
    average     NUMERIC
);

\copy results from results.txt (header true)

CREATE OR REPLACE FUNCTION gen_results(text) RETURNS TABLE(
    dataset   TEXT,
    extension TEXT,
    csv       NUMERIC,
    "csv.gz"  NUMERIC,
    tsv       NUMERIC,
    "tsv.gz"  NUMERIC,
    "json"    NUMERIC,
    "json.gz" NUMERIC,
    "Parquet" NUMERIC,
    "Arrow"   NUMERIC,
    "Avro"    NUMERIC
) LANGUAGE SQL AS $$
    WITH ext(ext) AS (SELECT DISTINCT extension FROM results)
    SELECT $1, ext,
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'CSV' AND compression = 'none'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'CSV' AND compression = 'gzip'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'TSV' AND compression = 'none'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'TSV' AND compression = 'gzip'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'JSON' AND compression = 'none'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'JSON' AND compression = 'gzip'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'Parquet'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'Arrow'),
          (SELECT average FROM results WHERE extension = ext AND dataset = $1 AND format = 'Avro')
      FROM ext
    ORDER BY ext
$$;

COPY (SELECT * FROM gen_results('logs')) TO STDOUT (NULL '', header true);
COPY (SELECT * FROM gen_results('taxi')) TO STDOUT (NULL '');

-- SELECT r.extension as extension, csv.average AS csv
--   FROM results r
--   JOIN results csv ON r.extension = csv.extension AND r.format = csv.format AND csv.format = 'CSV' AND r.compression = csv.compression AND csv.compression = 'none'
-- ;

ROLLBACK;
