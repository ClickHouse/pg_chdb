.PHONY: corpus # Create the data corpus.
corpus: mk-datasets.sh amazon.sql export-hacknernews.sql hackernews.sql logs.sql taxi_trips.sql
	@bash $<

.PHONY: sync # Upload the datasets to S3
sync: corpus
	@aws s3 sync logs s3://chdb-lakedata-public/logs
	@aws s3 sync taxi_trips s3://chdb-lakedata-public/taxi_trips
# 	@aws s3 sync amazon s3://chdb-lakedata-public/amazon
# 	@aws s3 sync hackernews s3://chdb-lakedata-public/hackernews

PSQL_OPTS := --quiet --no-psqlrc --no-align --tuples-only --set ON_ERROR_STOP=1
results.txt: pg_lake/results.tsv pg_duckdb/results.tsv aws_s3/results.tsv chdb/results.tsv
	@echo 'dataset	format	compression	run1	run2	run3	average' > $@
	@cat $^ >> $@

chdb/results.tsv: chdb/*.sql
	@psql $(PSQL_OPTS) -f chdb/logs.sql > $@
	@psql $(PSQL_OPTS) -f chdb/taxi.sql >> $@
# 	@psql $(PSQL_OPTS) -f chdb/amazon.sql >> $@
# 	@psql $(PSQL_OPTS) -f chdb/hackernews.sql >> $@

aws_s3/results.tsv: aws_s3/*.sql
	@psql $(PSQL_OPTS) -f aws_s3/logs.sql > $@
	@psql $(PSQL_OPTS) -f aws_s3/taxi.sql >> $@
# 	@psql $(PSQL_OPTS) -f aws_s3/amazon.sql >> $@
# 	@psql $(PSQL_OPTS) -f aws_s3/hackernews.sql >> $@

pg_duckdb/results.tsv: pg_duckdb/*.sql
	@psql $(PSQL_OPTS) -f pg_duckdb/logs.sql > $@
	@psql $(PSQL_OPTS) -f pg_duckdb/taxi.sql >> $@
# 	@psql $(PSQL_OPTS) -f pg_duckdb/amazon.sql >> $@
# 	@psql $(PSQL_OPTS) -f pg_duckdb/hackernews.sql >> $@

pg_lake/results.tsv: pg_lake/*.sql
	@psql $(PSQL_OPTS) -f pg_lake/logs.sql > $@
	@psql $(PSQL_OPTS) -f pg_lake/taxi.sql >> $@
# 	@psql $(PSQL_OPTS) -f pg_lake/amazon.sql >> $@
# 	@psql $(PSQL_OPTS) -f pg_lake/hackernews.sql >> $@

.PHONY: sync # Summarize results by extension with averages for each data set and format.
summary: summary.sql results.txt
	@psql $(PSQL_OPTS) -f $<
