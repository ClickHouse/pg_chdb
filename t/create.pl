#!/usr/bin/perl

use v5.34;
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use lib 't';
use chDBTestUtils;

my $node = PostgreSQL::Test::Cluster->new('create');
$node->init;
$node->append_conf(
    'postgresql.conf',
    qq{shared_preload_libraries = 'chdb_hook'\nlog_min_messages = DEBUG1},
);
$node->start;
END { $node->stop('fast') }

my $port = PostgreSQL::Test::Cluster::get_free_port;
my $dir = $node->basedir;

my $file_query = q{DESCRIBE TABLE file({path:String}, {format:String}, {structure:String}) SETTINGS describe_compact_output=1};

FILE: {
    check_query(
        $node, 'structure_from file',
        qq{CREATE TABLE inferred () WITH (structure_from = 'file://$dir/nonesuch.csv')},
        qr[Cannot stat file .*nonesuch\.csv],
        qr[\Q$file_query],
        qr[\Q{ path: "$dir/nonesuch.csv", format: "auto", structure: "auto" }],
    );

    # Infer columns before copying rows
    check_query(
        $node, 'copy_from file',
        qq{CREATE TABLE loaded () WITH (copy_from = 'file://$dir/nonesuch.csv')},
        qr[Cannot stat file .*nonesuch\.csv],
        qr[\Q$file_query],
        qr[\Q{ path: "$dir/nonesuch.csv", format: "auto", structure: "auto" }],
    );
}

STRUCTURE: {
    # Use explicit structure without reading source data
    $node->psql(postgres => qq{
        CREATE TABLE named () WITH (
            structure_from = 'file://$dir/nonesuch.csv',
            format = 'Parquet',
            structure = 'id Int64, name Nullable(String)'
        )
    });
    check_log(
        $node, 'structure_from file with structure',
        qr[\Q$file_query],
        qr[\Q{ path: "$dir/nonesuch.csv", format: "Parquet", structure: "id Int64, name Nullable(String)" }],
    );
    is $node->safe_psql(postgres => q{
        SELECT string_agg(
                   format('%s %s %s', attname, format_type(atttypid, atttypmod), attnotnull),
                   ', ' ORDER BY attnum
               )
          FROM pg_attribute WHERE attrelid = 'named'::regclass AND attnum > 0
    }), 'id bigint t, name text f', 'Should derive the columns from the structure';
}

S3: {
    check_query(
        $node, 'structure_from s3',
        qq{CREATE TABLE from_s3 () WITH (structure_from = 's3://localhost:$port/bucket/prefix/file.csv')},
        qr/\QHTTP response code: 403/,
        qr[\QDESCRIBE TABLE s3({url:String}, NOSIGN, {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000, describe_compact_output=1],
        qr[\Q{ url: "s3://localhost:\E$port\Q/bucket/prefix/file.csv", format: "auto", structure: "auto" }],
    );
}

done_testing;
