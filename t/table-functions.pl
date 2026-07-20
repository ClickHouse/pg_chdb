#!/usr/bin/perl

use v5.34;
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('table-functions');

# Set up utility test functions.
{
    # Fetch chdb_bgw log lines from offset.
    my $offset = 0;
    sub bgw_log($) {
        my $node = shift;
        my $data = slurp_file $node->logfile, $offset;
        $offset += length $data;
        return grep { /\bchdb_bgw\b/ } split /\n/, $data
            if $node->pg_version > 19;
        return split /\n/, $data
    }
}

# Compare hdb_bgw log lines immediately following a "executing chDB query" log
# line. The first should contain the chDB query with placeholders. The second
# should map the placeholders to values.
sub check_log {
    my ($file, $desc, $query_rx, $params_rx) = @_;
    my @lines = bgw_log $file;
    while (@lines && $lines[0] !~ /executing chDB query/) {
        shift @lines;
    }

    shift @lines;
    splice @lines, 2;
    is @lines, 2, "Should have 2 $desc log lines" || return;
    like $lines[0], $query_rx, "Should match $desc query";
    like $lines[1], $params_rx, "Should match $desc params";
}

# Test a given query's log values containing the resulting chDB query and
# associated parameters.
sub check_query {
    my ($node, $desc, $query, @args) = @_;
    subtest $desc => sub {
        eval { $node->safe_psql(postgres => $query) };
        ok $@, "Should have $desc chDB error";
        check_log $node, $desc, @args;
    };
}

$node->init;
$node->append_conf(
    'postgresql.conf',
    qq{shared_preload_libraries = 'chdb'\nlog_min_messages = DEBUG1},
);
$node->start;
END { $node->stop('fast') }

$node->safe_psql(postgres => 'CREATE EXTENSION chdb');
$node->safe_psql(postgres => 'CREATE TABLE stuff (id int)');
my $port = PostgreSQL::Test::Cluster::get_free_port;

subtest s3 => sub {
    check_query(
        $node, 'just FROM url',
        qq{COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv'},
        qr[\QSELECT * FROM s3({url:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 30000],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv" }],
    );
    check_query(
        $node, 'just TO url',
        qq{COPY stuff TO 's3://localhost:$port/bucket/prefix/file.csv'},
        qr[\QINSERT INTO FUNCTION s3('s3://localhost\E:$port\Q/bucket/prefix/file.csv') SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 30000],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv" }],
    );
    check_query(
        $node, 'FROM all params',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                access_key 'key',
                access_secret 'secret',
                session_token 'big fat token',
                format 'parquet',
                structure 'id Int64',
                compression 'lz4',
                timeout 0
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {access_key:String}, {access_secret:String}, {session_token:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", access_key: "key", access_secret: "secret", session_token: "big fat token", format: "parquet", structure: "id Int64", compression: "lz4" }],
    );
    check_query(
        $node, 'FROM with no secret',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                access_key 'key',
                session_token 'some token',
                format 'parquet',
                structure 'id Int64',
                compression 'lz4',
                timeout 0
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {access_key:String}, {access_secret:String}, {session_token:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", access_key: "key", access_secret: "", session_token: "some token", format: "parquet", structure: "id Int64", compression: "lz4" }],
    );
    check_query(
        $node, 'FROM with no token',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                access_key 'key',
                format 'parquet',
                structure 'id Int64',
                compression 'lz4',
                timeout 0
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {access_key:String}, {access_secret:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", access_key: "key", access_secret: "", format: "parquet", structure: "id Int64", compression: "lz4" }],
    );
    check_query(
        $node, 'FROM with no compression',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                format 'parquet',
                structure 'id Int64',
                timeout 0
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {format:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", format: "parquet", structure: "id Int64" }],
    );
    check_query(
        $node, 'FROM with no structure',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                format 'parquet',
                compression 'snappy',
                timeout 0
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", format: "parquet", structure: "auto", compression: "snappy" }],
    );
    check_query(
        $node, 'FROM with no format',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                compression 'snappy',
                timeout 0
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", format: "auto", structure: "auto", compression: "snappy" }],
    );
    check_query(
        $node, 'FROM with just format',
        qq{
            COPY stuff FROM 's3://localhost:$port/bucket/prefix/file.csv' (
                format 'tsv',
                timeout 100
            )
        },
        qr[\QSELECT * FROM s3({url:String}, {format:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 100],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", format: "tsv" }],
    );
};

subtest gcs => sub {
    # GCS passes url as https and ignores session_token. Otherwise the same as s3.
    check_query(
        $node, 'just FROM url',
        qq{COPY stuff FROM 'gcs://example.org/bucket/prefix/file.csv'},
        qr[\QSELECT * FROM gcs({url:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 30000],
        qr[\Q{ url: "https://example.org/bucket/prefix/file.csv" }],
    );
    check_query(
        $node, 'just TO url',
        qq{COPY stuff TO 'gcs://example.org/bucket/prefix/file.csv'},
        qr[\QINSERT INTO FUNCTION gcs('https://example.org/bucket/prefix/file.csv') SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 30000],
        qr[\Q{ url: "https://example.org/bucket/prefix/file.csv" }],
    );
    check_query(
        $node, 'FROM all params',
        qq{
            COPY stuff FROM 'gcs://example.org/bucket/prefix/file.csv' (
                access_key 'key',
                access_secret 'secret',
                session_token 'big fat token',
                format 'parquet',
                structure 'id Int64',
                compression 'lz4',
                timeout 0
            )
        },
        qr[\QSELECT * FROM gcs({url:String}, {access_key:String}, {access_secret:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, s3_request_timeout_ms = 0],
        qr[\Q{ url: "https://example.org/bucket/prefix/file.csv", access_key: "key", access_secret: "secret", format: "parquet", structure: "id Int64", compression: "lz4" }],
    );
};

subtest http => sub {
    # The url() function just takes url, format, and structure. Timeout is
    # seconds rather than ms.
    check_query(
        $node, 'just FROM url',
        qq{COPY stuff FROM 'http://example.org/path/file.csv'},
        qr[\QSELECT * FROM url({url:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, http_connection_timeout=30, http_max_tries=1],
        qr[\Q{ url: "http://example.org/path/file.csv" }],
    );
    check_query(
        $node, 'just TO url',
        qq{COPY stuff TO 'http://example.org/path/file.csv'},
        qr[\QINSERT INTO FUNCTION url('http://example.org/path/file.csv') SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, http_connection_timeout=30, http_max_tries=1],
        qr[\Q{ url: "http://example.org/path/file.csv" }],
    );
    check_query(
        $node, 'TO format, structure, round up timeout',
        qq{COPY stuff FROM 'http://example.org/path/file.csv' (FORMAT 'TabSeparated', structure 'id Int32', timeout 500)},
        qr[\QSELECT * FROM url({url:String}, {format:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, http_connection_timeout=1, http_max_tries=1],
        qr[\Q{ url: "http://example.org/path/file.csv", format: "TabSeparated", structure: "id Int32" }],
    );
    check_query(
        $node, 'TO structure, round up timeout',
        qq{COPY stuff FROM 'http://example.org/path/file.csv' (structure 'id Int32', timeout 1500)},
        qr[\QSELECT * FROM url({url:String}, {format:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, http_connection_timeout=2, http_max_tries=1],
        qr[\Q{ url: "http://example.org/path/file.csv", format: "auto", structure: "id Int32" }],
    );
    check_query(
        $node, 'TO format',
        qq{COPY stuff FROM 'http://example.org/path/file.csv' (format 'x UInt16', timeout 100)},
        qr[\QSELECT * FROM url({url:String}, {format:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, http_connection_timeout=1, http_max_tries=1],
        qr[\Q{ url: "http://example.org/path/file.csv", format: "x UInt16" }],
    );
};

subtest azure => sub {
    # The Azure URL must be converted, and requires all three of its parts
    # plus account_name and account_key. It also orders for the last three
    # options: format,compression,structure vs. format,structure,compression
    # for the others. Will be glad when ClickHouse adds
    # [named parameters](https://github.com/ClickHouse/ClickHouse/issues/108802).

    local $@;
    eval { $node->safe_psql(postgres => q{COPY stuff FROM 'az://no-dot/foo/bar'}) };
    like $@, qr/\Qchdb: Azure URL missing the storage account host/,
        'Should have error for invalid host name';

    $@ = undef;
    eval { $node->safe_psql(postgres => q{COPY stuff FROM 'az://example.com'}) };
    like $@, qr/\Qchdb: Azure URL missing the container name/,
        'Should have error for missing container name';

    $@ = undef;
    eval { $node->safe_psql(postgres => q{COPY stuff FROM 'az://example.com/'}) };
    like $@, qr/\Qchdb: Azure URL missing the container name/,
        'Should have error for no container name after slash';

    $@ = undef;
    eval { $node->safe_psql(postgres => q{COPY stuff FROM 'abfs://hi.example.com/'}) };
    like $@, qr/\Qchdb: Azure ABFS URL missing the container part/,
        'Should have error for no container in abfs URL';

    check_query(
        $node, 'just FROM azure',
        q{COPY stuff FROM 'az://example.org/path/file.csv'},
        qr[\QSELECT * FROM azureBlobStorage({url:String}, {container:String}, {path:String}, {account_name:String}, {account_key:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=30000],
        qr[\Q{ url: "https://example.org", container: "path", path: "file.csv", account_name: "", account_key: "" }],
    );
    check_query(
        $node, 'To azure with query',
        q{COPY stuff TO 'az://example.org/path/file.csv?x=y&abc=12'},
        qr[\QINSERT INTO FUNCTION azureBlobStorage('https://example.org?x=y&abc=12', 'path', 'file.csv', '', '') SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=30000],
        qr[\Q{ url: "https://example.org?x=y&abc=12", container: "path", path: "file.csv", account_name: "", account_key: "" }],
    );
    check_query(
        $node, 'FROM azure with no path',
        q{COPY stuff FROM 'az://example.org/container'},
        qr[\QSELECT * FROM azureBlobStorage({url:String}, {container:String}, {path:String}, {account_name:String}, {account_key:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=30000],
        qr[\Q{ url: "https://example.org", container: "container", path: "", account_name: "", account_key: "" }],
    );
    check_query(
        $node, 'FROM Azure with all args',
        q{
            COPY stuff FROM 'azure://acc.example.org/xyz/yep.csv' (
                access_key 'ac_name',
                access_secret 'ac_key',
                session_token 'big fat token',
                format 'tsv',
                structure 'id Int32',
                compression 'lz4',
                timeout 200
            )
        },
        qr[\QSELECT * FROM azureBlobStorage({url:String}, {container:String}, {path:String}, {account_name:String}, {account_key:String}, {format:String}, {compression:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=200],
        qr[\Q{ url: "https://acc.example.org", container: "xyz", path: "yep.csv", account_name: "ac_name", account_key: "ac_key", format: "tsv", compression: "lz4", structure: "id Int32" }],
    );

    check_query(
        $node, 'FROM abfs with compression & structure',
        q{COPY stuff FROM 'abfs://container@account/xyz/yep.csv' (access_key 'ac-key', compression 'snappy', structure 'x String')},
        qr[\QSELECT * FROM azureBlobStorage({url:String}, {container:String}, {path:String}, {account_name:String}, {account_key:String}, {format:String}, {compression:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=30000],
        qr[\Q{ url: "https://account.blob.core.windows.net", container: "container", path: "xyz/yep.csv", account_name: "ac-key", account_key: "", format: "auto", compression: "snappy", structure: "x String" }],
    );

    check_query(
        $node, 'FROM abfss host with structure',
        q{COPY stuff FROM 'abfss://hi@example.org/xyz/yep.csv' (access_key 'ac-key', structure 'x String')},
        qr[\QSELECT * FROM azureBlobStorage({url:String}, {container:String}, {path:String}, {account_name:String}, {account_key:String}, {format:String}, {compression:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=30000],
        qr[\Q{ url: "https://example.org", container: "hi", path: "xyz/yep.csv", account_name: "ac-key", account_key: "", format: "auto", compression: "", structure: "x String" }],
    );

    check_query(
        $node, 'FROM no-path abfs with format only',
        q{COPY stuff FROM 'abfs://slick@example.org' (format 'z Int8')},
        qr[\QSELECT * FROM azureBlobStorage({url:String}, {container:String}, {path:String}, {account_name:String}, {account_key:String}, {format:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1, azure_request_timeout_ms=30000],
        qr[\Q{ url: "https://example.org", container: "slick", path: "", account_name: "", account_key: "", format: "z Int8" }],
    );
};

subtest file => sub {
    # No relative path.
    local $@;
    eval { $node->safe_psql(postgres => q{COPY stuff FROM 'file://hi.csv'}) };
    like $@, qr/\Qchdb: relative path not allowed for COPY to file URL/,
        'Should have error for relative path';

    my $dir = $node->basedir;
    check_query(
        $node, 'just FROM file',
        qq{COPY stuff FROM 'file://$dir/nonesuch.csv'},
        qr[\QSELECT * FROM file({path:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ path: "$dir/nonesuch.csv" }],
    );

    check_query(
        $node, 'just TO file',
        qq{COPY stuff TO 'file://$dir/nonesuch.csv'},
        qr[\QINSERT INTO FUNCTION file('$dir/nonesuch.csv') SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ path: "$dir/nonesuch.csv" }],
    );

    check_query(
        $node, 'all options',
        qq{COPY stuff FROM 'file://$dir/nonesuch.csv' (compression 'lz4', structure 'z Int8', format 'tsv')},
        qr[\QSELECT * FROM file({path:String}, {format:String}, {structure:String}, {compression:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ path: "$dir/nonesuch.csv", format: "tsv", structure: "z Int8", compression: "lz4" }],
    );
};

subtest hdfs => sub {
    check_query(
        $node, 'just FROM url',
        qq{COPY stuff FROM 'hdfs://localhost:$port/bucket/prefix/file.csv'},
        qr[\QSELECT * FROM hdfs({url:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ url: "hdfs://localhost:\E$port\Q/bucket/prefix/file.csv" }],
    );
    check_query(
        $node, 'just TO url',
        qq{COPY stuff TO 'hdfs://localhost:$port/bucket/prefix/file.csv'},
        qr[\QINSERT INTO FUNCTION hdfs('hdfs://localhost:\E$port\Q/bucket/prefix/file.csv') SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ url: "hdfs://localhost:\E$port\Q/bucket/prefix/file.csv" }],
    );
    check_query(
        $node, 'FROM url with format and structure',
        qq{COPY stuff FROM 'hdfs://localhost:$port/bucket/prefix/file.csv' (FORMAT 'TSV', STRUCTURE 'a Int8')},
        qr[\QSELECT * FROM hdfs({url:String}, {format:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ url: "hdfs://localhost:\E$port\Q/bucket/prefix/file.csv", format: "TSV", structure: "a Int8" }],
    );
    check_query(
        $node, 'FROM url with structure',
        qq{COPY stuff FROM 'hdfs://localhost:$port/bucket/prefix/file.csv' (STRUCTURE 'a UInt8')},
        qr[\QSELECT * FROM hdfs({url:String}, {format:String}, {structure:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ url: "hdfs://localhost:\E$port\Q/bucket/prefix/file.csv", format: "auto", structure: "a UInt8" }],
    );
    check_query(
        $node, 'FROM url with format',
        qq{COPY stuff FROM 'hdfs://localhost:$port/bucket/prefix/file.csv' (format 'TabSeparated')},
        qr[\QSELECT * FROM hdfs({url:String}, {format:String}) SETTINGS date_time_output_format='iso', engine_file_truncate_on_insert=1],
        qr[\Q{ url: "hdfs://localhost:\E$port\Q/bucket/prefix/file.csv", format: "TabSeparated" }],
    );
};

done_testing;
