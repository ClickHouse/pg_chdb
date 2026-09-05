-- https://github.com/ClickHouse/ClickHouse/issues/29693#issuecomment-4755761107

CREATE TABLE hackernews_history UUID '259cf9f0-0c4f-451d-9029-7de661f9a085'
(
    update_time DateTime DEFAULT now(), id UInt32, deleted UInt8,
    type Enum8('story'=1,'comment'=2,'poll'=3,'pollopt'=4,'job'=5),
    by LowCardinality(String), time DateTime, text String, dead UInt8,
    parent UInt32, poll UInt32, kids Array(UInt32), url String, 
    score Int32, title String, parts Array(UInt32), descendants Int32
)   
ENGINE = ReplacingMergeTree(update_time)
ORDER BY id
SETTINGS refresh_parts_interval = 60,
    disk = disk(readonly = true, type = 's3_plain_rewritable',
                endpoint = 'https://clicklake-test-2.s3.eu-central-1.amazonaws.com/',
                use_environment_credentials = false);

SET date_time_output_format='iso';

SELECT * FROM hackernews_history LIMIT 10 INTO OUTFILE 'ch-hackernews.csv.gz';
