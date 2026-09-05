CREATE EXTENSION IF NOT EXISTS pg_lake_copy CASCADE;

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
    url      TEXT;
   _timing   timestamptz;
   _start_ts timestamptz;
   _end_ts   timestamptz;
   _overhead numeric;     -- in ms
   _result   numeric;
   timings   numeric[];
   head      TEXT := CASE WHEN fmt IN ('CSV') THEN 'header true,' ELSE '' END;
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
        FOREACH url IN ARRAY paths LOOP
            url := format('https://chdb-lakedata-public.s3.us-east-2.amazonaws.com/%s', url);
            query := format('COPY target FROM %L (%s format %L)', url, head, fmt);
            _start_ts := clock_timestamp();
            EXECUTE query;
            _end_ts   := clock_timestamp();
            _result = _result + round(1000 * (extract(epoch FROM _end_ts - _start_ts)) - _overhead, 4);
        END LOOP;
        timings = array_append(timings, _result);
        TRUNCATE target;
    END LOOP;

    -- Report.
    SELECT round(avg(i), 4) FROM unnest(timings) i INTO _result;
    RETURN QUERY SELECT 'pg_lake', ds, fmt, press, timings[1], timings[2], timings[3], _result;
END
$$;
