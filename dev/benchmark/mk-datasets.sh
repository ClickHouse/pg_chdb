#!/bin/bash

set -e

export WORKDIR="${WORKDIR:-"$PWD"}"
mkdir -p "$WORKDIR"

declare -A source_for
source_for[amazon]=https://datasets-documentation.s3.eu-west-3.amazonaws.com/amazon_reviews/amazon_reviews_2015.snappy.parquet
source_for[taxi_trips]=https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/trips_1.gz
source_for[hackernews]=ch-hackernews.csv.gz
source_for[logs]=

for k in "${!source_for[@]}"; do
    printf '######## %s ########\n' "$k"
    mkdir -p "$k"
    cd "$k"

    if [ -n "${source_for[$k]}" ]; then
        file="$(basename "${source_for[$k]}")"
        if [ ! -e "$file" ]; then
            printf 'Downloading %s\n' "$file"
            if [ "$k" = "hackernews" ]; then
                clickhouse local --queries-file ../export-hacknernews.sql
            else
                curl -o "$file" "${source_for[$k]}"
                if [ "$k" = "taxi_trips" ]; then
                    # Remove invalid UTF-8 from taxi_trips data.
                    gunzip "$file"
                    iconv -f utf-8 -t utf-8 -c trips_1 > trips_1.new
                    mv trips_1.new trips_1
                    gzip trips_1
                fi
            fi
        fi
    fi

    export WORKDIR="$PWD"
    psql -Xqf "../$k.sql"
    cd ..
    printf 'Done\n\n'
done
