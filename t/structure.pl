#!/usr/bin/perl

use v5.34;
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use lib 't';
use chDBTestUtils;

my $node = PostgreSQL::Test::Cluster->new('structure');
$node->init;
$node->append_conf(
    'postgresql.conf',
    qq{shared_preload_libraries = 'chdb_hook'\nlog_min_messages = DEBUG1},
);
$node->start;
END { $node->stop('fast') }

my $port = PostgreSQL::Test::Cluster::get_free_port;
my $dir = $node->basedir;

NUMBERS: {
    my $oid8 = $node->pg_version->major >= 19 ? 'OID8' : 'XID8';
    $node->psql(postgres => qq{
        CREATE TABLE numbers (
            i2  INT2           NOT NULL,
            i4  INT4           NOT NULL,
            i8  INT8               NULL,
            num numeric            NULL,
            np  numeric(32)        NULL,
            nps numeric(12, 6)     NULL,
            f4  float4         NOT NULL,
            f8  float8             NULL,
            b   bool           NOT NULL,
            o   OID            NOT NULL,
            o8  $oid8          NOT NULL
        )
    });
    check_query(
        $node, 'numbers',
        qq{COPY numbers FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "i2 Int16, i4 Int32, i8 Nullable(Int64), num Nullable(Decimal256(38)), np Nullable(Decimal(32,0)), nps Nullable(Decimal(12,6)), f4 Float32, f8 Nullable(Float64), b Bool, o UInt32, o8 UInt64" }],
    );

    $node->psql(postgres => qq{
        CREATE TABLE number_arrays (
            i2  INT2[]           NOT NULL,
            i4  INT4[]           NOT NULL,
            i8  INT8[]           NOT NULL,
            num numeric[]        NOT NULL,
            np  numeric(32)[]    NOT NULL,
            nps numeric(12, 6)[] NOT NULL,
            f4  float4[]         NOT NULL,
            f8  float8[]         NOT NULL,
            b   bool[]           NOT NULL,
            o   OID[]            NOT NULL,
            o8  ${oid8}[]          NOT NULL
        )
    });
    check_query(
        $node, 'number arrays',
        qq{COPY number_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "i2 Array(Nullable(Int16)), i4 Array(Nullable(Int32)), i8 Array(Nullable(Int64)), num Array(Nullable(Decimal256(38))), np Array(Nullable(Decimal(32,0))), nps Array(Nullable(Decimal(12,6))), f4 Array(Nullable(Float32)), f8 Array(Nullable(Float64)), b Array(Nullable(Bool)), o Array(Nullable(UInt32)), o8 Array(Nullable(UInt64))" }],
    );
}

STRINGS: {
    $node->psql(postgres => q{
        CREATE TABLE strings (
            t  TEXT    NOT NULL,
            ba BYTEA   NOT NULL,
            n  NAME        NULL
        )
    });
    check_query(
        $node, 'strings',
        qq{COPY strings FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "t String, ba String, n Nullable(String)" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE string_arrays (
            t  TEXT[]    NOT NULL,
            ba BYTEA[]   NOT NULL,
            n  NAME[]    NOT NULL
        )
    });
    check_query(
        $node, 'string arrays',
        qq{COPY string_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "t Array(Nullable(String)), ba Array(Nullable(String)), n Array(Nullable(String))" }],
    );
}

FIXIES: {
    $node->psql(postgres => q{
        CREATE TABLE fixies (
            cr  character(6) NOT NULL,
            ch  char(12)     NOT NULL,
            bp  bpchar       NOT NULL,
            pbn bpchar(8)    NOT NULL
        )
    });
    check_query(
        $node, 'fixed strings',
        qq{COPY fixies FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "cr String, ch String, bp String, pbn String" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE fixie_arrays (
            cr  character(6)[] NOT NULL,
            ch  char(12)[]     NOT NULL,
            bp  bpchar[]       NOT NULL,
            pbn bpchar(8)[]    NOT NULL
        )
    });
    check_query(
        $node, 'fixed string arrays',
        qq{COPY fixie_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "cr Array(Nullable(String)), ch Array(Nullable(String)), bp Array(Nullable(String)), pbn Array(Nullable(String))" }],
    );
}

AS_STRINGS: {
    $node->psql(postgres => q{
        CREATE TABLE non_strings (
            ival INTERVAL NOT NULL,
            tsv  tsvector NOT NULL,
            tsq  tsquery  NOT NULL,
            jp   jsonpath NOT NULL,
            mon  money    NOT NULL,
            xml  XML      NOT NULL,
            na   int[]       NULL
        )
    });
    check_query(
        $node, 'non strings as strings',
        qq{COPY non_strings FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ival String, tsv String, tsq String, jp String, mon String, xml String, na Array(Nullable(Int32))" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE non_string_arrays (
            ival INTERVAL[] NOT NULL,
            tsv  tsvector[] NOT NULL,
            tsq  tsquery[]  NOT NULL,
            jp   jsonpath[] NOT NULL,
            mon  money[]    NOT NULL,
            xml  XML[]      NOT NULL,
            na   int[]          NULL
        )
    });
    check_query(
        $node, 'no strings as string arrays',
        qq{COPY non_string_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ival Array(Nullable(String)), tsv Array(Nullable(String)), tsq Array(Nullable(String)), jp Array(Nullable(String)), mon Array(Nullable(String)), xml Array(Nullable(String)), na Array(Nullable(Int32))" }],
    );
}

VARCHAR: {
    $node->psql(postgres => q{
        CREATE TABLE varchars (
            vc  VARCHAR    NOT NULL,
            vcn VARCHAR(8) NOT NULL,
            bc  VARBIT     NOT NULL,
            bcn VARBIT(4)  NOT NULL
        )
    });
    check_query(
        $node, 'varchars',
        qq{COPY varchars FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "vc String, vcn String, bc String, bcn String" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE varchar_arrays (
            vc  VARCHAR[]    NOT NULL,
            vcn VARCHAR(8)[] NOT NULL,
            bc  VARBIT[]     NOT NULL,
            bcn VARBIT(4)[]  NOT NULL
        )
    });
    check_query(
        $node, 'varchar arrayss',
        qq{COPY varchar_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "vc Array(Nullable(String)), vcn Array(Nullable(String)), bc Array(Nullable(String)), bcn Array(Nullable(String))" }],
    );
}

JSON_UUID: {
    $node->psql(postgres => q{
        CREATE TABLE json_uuid (
            u  UUID   NOT NULL,
            j  JSON   NOT NULL,
            jb JSONB      NULL
        )
    });
    check_query(
        $node, 'json & uuid',
        qq{COPY json_uuid FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "u UUID, j String, jb Nullable(String)" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE json_uuid_arrays (
            u  UUID[]   NOT NULL,
            j  JSON[]   NOT NULL,
            jb JSONB[]  NOT NULL
        )
    });
    check_query(
        $node, 'json & uuid arrays',
        qq{COPY json_uuid_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "u Array(Nullable(UUID)), j Array(Nullable(String)), jb Array(Nullable(String))" }],
    );
}

GEO: {
    $node->psql(postgres => q{
        CREATE TABLE geos (
            p   point    NOT NULL,
            line line    NOT NULL,
            lseg lseg    NOT NULL,
            box  box     NOT NULL,
            path path    NOT NULL,
            poly polygon NOT NULL,
            cir  circle  NOT NULL
        )
    });
    check_query(
        $node, 'geometric',
        qq{COPY geos FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "p Point, line Tuple(a Float64, b Float64, c Float64), lseg LineString, box Tuple(high Point, low Point), path LineString, poly Ring, cir Tuple(center Point, radius Float64)" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE geo_arrays (
            p   point[]    NOT NULL,
            line line[]    NOT NULL,
            lseg lseg[]    NOT NULL,
            box  box[]     NOT NULL,
            path path[]    NOT NULL,
            poly polygon[] NOT NULL,
            cir  circle[]  NOT NULL
        )
    });
    check_query(
        $node, 'geometric arrays',
        qq{COPY geo_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "p Array(Nullable(Point)), line Array(Nullable(Tuple(a Float64, b Float64, c Float64))), lseg Array(LineString), box Array(Nullable(Tuple(high Point, low Point))), path Array(LineString), poly Array(Ring), cir Array(Nullable(Tuple(center Point, radius Float64)))" }],
    );
}

DATETIME: {
    $node->psql(postgres => q{
        CREATE TABLE datetime (
            ts    TIMESTAMP          NULL,
            tsn   TIMESTAMP(3)       NULL,
            tstz  TIMESTAMPTZ    NOT NULL,
            tstzn TIMESTAMPTZ(4) NOT NULL,
            date  DATE           NOT NULL,
            time  TIME           NOT NULL,
            timen TIME(3)        NOT NULL,
            ttz   TIMETZ         NOT NULL,
            ttzn  TIMETZ(3)      NOT NULL,
            ival  INTERVAL       NOT NULL
        )
    });
    check_query(
        $node, 'datetime',
        qq{COPY datetime FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ts Nullable(DateTime64(6, 'UTC')), tsn Nullable(DateTime64(6, 'UTC')), tstz DateTime64(6, 'UTC'), tstzn DateTime64(6, 'UTC'), date Date32, time Time64(6), timen Time64(6), ttz String, ttzn String, ival String" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE datetime_arrays (
            ts    TIMESTAMP[]      NOT NULL,
            tsn   TIMESTAMP(3)[]   NOT NULL,
            tstz  TIMESTAMPTZ[]    NOT NULL,
            tstzn TIMESTAMPTZ(4)[] NOT NULL,
            date  DATE[]           NOT NULL,
            time  TIME[]           NOT NULL,
            timen TIME(3)[]        NOT NULL,
            ttz   TIMETZ[]         NOT NULL,
            ttzn  TIMETZ(3)[]      NOT NULL,
            ival  INTERVAL[]       NOT NULL
        )
    });
    check_query(
        $node, 'datetime arrays',
        qq{COPY datetime_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ts Array(Nullable(DateTime64(6, 'UTC'))), tsn Array(Nullable(DateTime64(6, 'UTC'))), tstz Array(Nullable(DateTime64(6, 'UTC'))), tstzn Array(Nullable(DateTime64(6, 'UTC'))), date Array(Nullable(Date32)), time Array(Nullable(Time64(6))), timen Array(Nullable(Time64(6))), ttz Array(Nullable(String)), ttzn Array(Nullable(String)), ival Array(Nullable(String))" }],
    );
}

ENUMS: {
    $node->psql(postgres => q{
        CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
    });
    $node->psql(postgres => q{
        CREATE TYPE dow AS ENUM ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
    });

    $node->psql(postgres => q{
        CREATE TABLE enums (
            mood mood NOT NULL,
            dow  dow  NOT NULL
        )
    });
    check_query(
        $node, 'enums',
        qq{COPY enums FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "mood String, dow String" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE enum_arrays (
            mood mood[] NOT NULL,
            dow  dow[]  NOT NULL
        )
    });
    check_query(
        $node, 'enum arrays',
        qq{COPY enum_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "mood Array(Nullable(String)), dow Array(Nullable(String))" }],
    );
}

NETS: {
    $node->psql(postgres => q{
        CREATE TABLE nets (
            inet INET     NOT NULL,
            cidr CIDR     NOT NULL,
            mac  MACADDR  NOT NULL,
            mac8 MACADDR8 NOT NULL
        )
    });
    check_query(
        $node, 'network addresses',
        qq{COPY nets FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "inet String, cidr String, mac String, mac8 String" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE net_arrays (
            inet INET[]     NOT NULL,
            cidr CIDR[]     NOT NULL,
            mac  MACADDR[]  NOT NULL,
            mac8 MACADDR8[] NOT NULL
        )
    });
    check_query(
        $node, 'network address arrays',
        qq{COPY net_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "inet Array(Nullable(String)), cidr Array(Nullable(String)), mac Array(Nullable(String)), mac8 Array(Nullable(String))" }],
    );
}

BITS: {
    $node->psql(postgres => q{
        CREATE TABLE bits (
            b  BIT       NOT NULL,
            bn BIT(3)    NOT NULL,
            vb varbit(6) NOT NULL
        )
    });
    check_query(
        $node, 'bit strings',
        qq{COPY bits FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "b String, bn String, vb String" }],
    );

    $node->psql(postgres => q{
        CREATE TABLE bit_arrays (
            b  BIT[]       NOT NULL,
            bn BIT(3)[]    NOT NULL,
            vb varbit(6)[] NOT NULL

        )
    });
    check_query(
        $node, 'bit string arrays',
        qq{COPY bit_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "b Array(Nullable(String)), bn Array(Nullable(String)), vb Array(Nullable(String))" }],
    );
}

NAMING: {
    $node->psql(postgres => q{
        CREATE TABLE "Namings" (
            "ID"        INT  NOT NULL,
            "Full Name" TEXT NOT NULL
        )
    });

    check_query(
        $node, 'quote identifiers',
        qq{COPY "Namings" FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ID Int32, "Full Name" String" }],
    );
}

done_testing;
