CREATE EXTENSION IF NOT EXISTS aws_s3 CASCADE;

/*
\set access_key ''
\set access_secret ''
\set session_token ''
\getenv access_key AWS_ACCESS_KEY_ID
\getenv access_secret AWS_SECRET_ACCESS_KEY
\getenv session_token AWS_SESSION_TOKEN

SELECT :'access_key' = '' OR :'access_secret' = '' AS no_creds \gset

-- Bail if no credentials.
\if :no_creds
\warn '######################################################################'
\warn '#                                                                    #'
\warn '#           No AWS credentials found in the environment              #'
\warn '#                                                                    #'
\warn '# Set the following environment variables to enable AWS auth:        #'
\warn '#                                                                    #'
\warn '# *   AWS_ACCESS_KEY_ID                                              #'
\warn '# *   AWS_SECRET_ACCESS_KEY                                          #'
\warn '# *   AWS_SESSION_TOKEN                                              #'
\warn '#                                                                    #'
\warn '######################################################################'
\warn ''
\quit
\endif

SELECT aws_commons.create_aws_credentials(
    :'access_key', :'access_secret', :'session_token'
) AS creds \gset

*/

CREATE OR REPLACE FUNCTION load_target(ds TEXT, fmt TEXT, press TEXT, VARIADIC paths TEXT[]) RETURNS TABLE (
    extension   TEXT,
    dataset     TEXT,
    format      TEXT,
    compression TEXT,
    run1        NUMERIC,
    run2        NUMERIC,
    run3        NUMERIC,
    average     NUMERIC
) LANGUAGE plpgsql AS $$
DECLARE
    path     TEXT;
   _timing   timestamptz;
   _start_ts timestamptz;
   _end_ts   timestamptz;
   _overhead numeric;     -- in ms
   _result   numeric;
   timings   numeric[];
   options   TEXT := format('(format %L, header true)', lower(fmt));
   query     TEXT;
BEGIN
    -- Measure execution overhead.
    FOR i IN 1..3 LOOP
        _timing  := clock_timestamp();
        _start_ts := clock_timestamp();
        EXECUTE 'SELECT 1';
        _end_ts   := clock_timestamp();
        -- take minimum duration as conservative estimate
        _result := 1000 * GREATEST(0, extract(epoch FROM LEAST(
            _start_ts - _timing,
            _end_ts   - _start_ts
        )));
        timings = array_append(timings, _result);
    END LOOP;
    SELECT avg(i) FROM unnest(timings) i INTO _overhead;

    -- Measure copy performance.
    timings = '{}';
    FOR i IN 1..3 LOOP
        _result := 0;
        FOREACH path IN ARRAY paths LOOP
            query := format(
                'SELECT aws_s3.table_import_from_s3(%L, %L, %L, aws_commons.create_s3_uri(%L, %L, %L))',
                'target', '', options, 'chdb-lakedata-public', path, 'us-east-2'
            );
            _start_ts := clock_timestamp();
            EXECUTE query;
            _end_ts   := clock_timestamp();
            _result = _result + round(1000 * (extract(epoch FROM _end_ts - _start_ts)) - _overhead, 4);
        END LOOP;
        timings = array_append(timings, _result);
        TRUNCATE target;
    END LOOP;

    -- Report the average.
    SELECT round(avg(i), 4) FROM unnest(timings) i INTO _result;
    RETURN QUERY SELECT 'aws_s3', ds, CASE lower(fmt) WHEN 'text' THEN 'TSV' ELSE fmt END,
                        press, timings[1], timings[2], timings[3], _result;
END
$$;
