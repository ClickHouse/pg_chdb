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
    qq{shared_preload_libraries = 'chdb'\nlog_min_messages = DEBUG1},
);
$node->start;
END { $node->stop('fast') }

$node->safe_psql(postgres => 'CREATE EXTENSION chdb');
my $port = PostgreSQL::Test::Cluster::get_free_port;
my $dir = $node->basedir;

NUMBERS: {
    $node->safe_psql(postgres => q{
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
            o8  OID8           NOT NULL
        )
    });
    check_query(
        $node, 'numbers',
        qq{COPY numbers FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "i2 Int16, i4 Int32, i8 Int64 NULL, num Decimal256(38) NULL, np Decimal(32,0) NULL, nps Decimal(12,6) NULL, f4 Float32, f8 Float64 NULL, b Bool, o UInt32, o8 UInt64" }],
        # qr[\Q structure: "i2 Int16, i4 Int32, i8 Int64 NULL, num Decimal256(38) NULL, np Decimal(32,0) NULL, nps Decimal(12,6) NULL, f4 Float32, f8 Float64 NULL, b Bool, o UInt32, o8 UInt64" }],
    );

    $node->safe_psql(postgres => q{
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
            o8  OID8[]           NOT NULL
        )
    });
    check_query(
        $node, 'number arrays',
        qq{COPY number_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "i2 String, i4 String, i8 String, num String, np String, nps String, f4 String, f8 String, b String, o String, o8 String" }],
        # qr[\Q structure: "i2 Array(Int16), i4 Array(Int32), i8 Array(Int64), num Array(Decimal256(38)), np Array(Decimal(32,0)), nps Array(Decimal(12,6)), f4 Array(Float32), f8 Array(Float64), b Array(Bool), o Array(UInt32), o8 Array(UInt64)" }],
    );
}

STRINGS: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "t String, ba String, n String NULL" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "t String, ba String, n String" }],
        # qr[\Q structure: "t Array(String), ba Array(String), n Array(String)" }],
    );
}

FIXIES: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "cr String(6), ch String(12), bp String, pbn String(8)" }],
        # qr[\Q structure: "cr FixedString(6), ch FixedString(12), bp String, pbn FixedString(8)" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "cr String, ch String, bp String, pbn String" }],
        # qr[\Q structure: "cr Array(FixedString(6)), ch Array(FixedString(12)), bp Array(String), pbn Array(FixedString(8))" }],
    );
}

AS_STRINGS: {
    $node->safe_psql(postgres => q{
        CREATE TABLE non_strings (
            ival INTERVAL NOT NULL,
            tsv  tsvector NOT NULL,
            tsq  tsquery  NOT NULL,
            jp   jsonpath NOT NULL,
            mon  money    NOT NULL,
            xml  XML      NOT NULL,
            cir  circle   NOT NULL,
            na   int[]       NULL
        )
    });
    check_query(
        $node, 'non strings as strings',
        qq{COPY non_strings FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ival String, tsv String, tsq String, jp String, mon String, xml String, cir String, na String" }],
    );

    $node->safe_psql(postgres => q{
        CREATE TABLE non_string_arrays (
            ival INTERVAL[] NOT NULL,
            tsv  tsvector[] NOT NULL,
            tsq  tsquery[]  NOT NULL,
            jp   jsonpath[] NOT NULL,
            mon  money[]    NOT NULL,
            xml  XML[]      NOT NULL,
            cir  circle[]   NOT NULL,
            na   int[]          NULL
        )
    });
    check_query(
        $node, 'no strings as string arrays',
        qq{COPY non_string_arrays FROM 'file://$dir/nonesuch.csv'},
        qr/nonesuch.csv doesn't exist/,
        qr[\QSELECT * FROM file],
        qr[\Q structure: "ival String, tsv String, tsq String, jp String, mon String, xml String, cir String, na String" }],
        # qr[\Q structure: "ival Array(String), tsv Array(String), tsq Array(String), jp Array(String), mon Array(String), xml Array(String), cir Array(String), na String" }],
    );
}

VARCHAR: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "vc String, vcn String(8), bc String, bcn String(4)" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "vc String, vcn String, bc String, bcn String" }],
        # qr[\Q structure: "vc Array(String), vcn Array(String(8)), bc Array(String), bcn Array(String(4))" }],
    );
}

JSON_UUID: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "u UUID, j String, jb String NULL" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "u String, j String, jb String" }],
        # qr[\Q structure: "u Array(UUID), j Array(JSON), jb Array(JSON)" }],
    );
}

GEO: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "p Point, line String, lseg String, box String, path String, poly String, cir String" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "p String, line String, lseg String, box String, path String, poly String, cir String" }],
        # qr[\Q structure: "p Array(Point), line Array(String), lseg Array(LineString), box Array(Polygon), path Array(LineString), poly Array(Polygon), cir Array(String)" }],
    );
}

DATETIME: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "ts String NULL, tsn String NULL, tstz DateTime64(6, 'UTC'), tstzn DateTime64(6, 'UTC'), date Date32, "time" Time64(6), timen Time64(6), ttz String, ttzn String, ival String" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "ts String, tsn String, tstz String, tstzn String, date String, "time" String, timen String, ttz String, ttzn String, ival String" }],
        # qr[\Q structure: "ts Array(String), tsn Array(String), tstz Array(DateTime64(6, 'UTC')), tstzn Array(DateTime64(6, 'UTC')), date Array(Date32), "time" Array(Time64(6)), timen Array(Time64(6)), ttz Array(Time64(6)), ttzn Array(Time64(6)), ival Array(String)" }],
    );
}

ENUMS: {
    $node->safe_psql(postgres => q{
        CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
    });
    $node->safe_psql(postgres => q{
        CREATE TYPE dow AS ENUM ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
    });

    $node->safe_psql(postgres => q{
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

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "mood String, dow String" }],
        # qr[\Q structure: "mood Array(String), dow Array(String)" }],
    );
}

NETS: {
    $node->safe_psql(postgres => q{
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

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "inet String, cidr String, mac String, mac8 String" }],
        # qr[\Q structure: "inet Array(String), cidr Array(String), mac Array(String), mac8 Array(String)" }],
    );
}

BITS: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "b FixedString(1), bn FixedString(3), vb String(6)" }],
    );

    $node->safe_psql(postgres => q{
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
        qr[\Q structure: "b String, bn String, vb String" }],
        # qr[\Q structure: "b Array(FixedString(1)), bn Array(FixedString(3)), vb Array(String(6))" }],
    );
}

NAMING: {
    $node->safe_psql(postgres => q{
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
        qr[\Q structure: ""ID" Int32, "Full Name" String" }],
    );
}

done_testing;
