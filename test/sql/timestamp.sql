LOAD 'chdb_hook';
SET datestyle TO ISO;

CREATE TABLE date_times (
    id INT,
    ts TIMESTAMP,
    tstz TIMESTAMPTZ
);

INSERT INTO date_times
VALUES (1, '2026-08-28T12:00:00', '2026-08-28T12:00:00Z')
     , (2, '2026-08-28T11:00:00', '2026-08-28T11:00:00 America/Los_Angeles')
     , (3, '2026-08-28T10:00:00', '2026-08-28T10:00:00.723923 Asia/Tokyo')
;
SELECT * FROM date_times ORDER BY id;

\set temp_dir /tmp/chdb-timestamp.tmp
\set tsv_path :temp_dir /date_times.tsv 
\set tsv_url file:// :tsv_path

-- timestamp values converted to UTC relative to Postgres timezone setting.
-- timestamptz values should always emit the same UTC output, regardless of
-- timezone setting. All values should be output using chDB's
-- `date_time_output_format='iso'` setting (`YYYY-MM-DDThh:mm:ssZ`).

/************************ America/Los_Angeles ************************/
-- timestamp values should be offset 7 hours.
SET timezone TO 'America/Los_Angeles';
COPY date_times TO :'tsv_url';
SELECT pg_read_file(:'tsv_path');

-- Should load identical values.
CREATE TABLE dt2 (LIKE date_times INCLUDING ALL);
COPY dt2 FROM :'tsv_url';
SELECT * FROM dt2 ORDER BY id;

-- Load with different TZ, ts values differ but tstz the same.
SET timezone TO 'America/New_York';
TRUNCATE dt2;
COPY dt2 FROM :'tsv_url';
SET timezone TO 'America/Los_Angeles';
SELECT * FROM dt2 ORDER BY id;

-- Different time zone defined in structure does not impact output, but
-- precision does.
COPY date_times TO :'tsv_url' (structure 'id Int8, ts DateTime64(3, ''Japan''), tstz DateTime64(6, ''UTC'')');
SELECT pg_read_file(:'tsv_path');

/************************ America/New_York ************************/
-- timestamp values should be offset 4 hours, timestamptz values unchanged.
SET timezone TO 'America/New_York';
COPY date_times TO :'tsv_url';
SELECT pg_read_file(:'tsv_path');

-- Time zone ignored in structure, precision respected.
COPY date_times TO :'tsv_url' (structure 'id Int8, ts DateTime64(3, ''Japan''), tstz DateTime64(6, ''UTC'')');
SELECT pg_read_file(:'tsv_path');

/************************ Asia/Tokyo ************************/
-- timestamp values should be offset 9 hours, timestamptz values unchanged.
SET timezone TO 'Asia/Tokyo';
COPY date_times TO :'tsv_url';
SELECT pg_read_file(:'tsv_path');

-- Time zone ignored in structure, precision respected.
COPY date_times TO :'tsv_url' (structure 'id Int8, ts DateTime64(3, ''Japan''), tstz DateTime64(3, ''America/New_York'')');
SELECT pg_read_file(:'tsv_path');

/************************ UTC ************************/
-- timestamp values should not be offset, timestamptz values unchanged.
SET timezone TO 'UTC';
COPY date_times TO :'tsv_url';
SELECT pg_read_file(:'tsv_path');

-- Time zone ignored in structure, precision respected.
COPY date_times TO :'tsv_url' (structure 'id Int8, ts DateTime64(3, ''Japan''), tstz DateTime64(3, ''America/New_York'')');
SELECT pg_read_file(:'tsv_path');


\! rm -rf /tmp/chdb-timestamp.tmp 2> /dev/null || true
