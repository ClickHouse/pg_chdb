#!/usr/bin/perl

use v5.34;
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use lib 't';
use chDBTestUtils;

# No AWS credentials are needed: every URL names a port nothing listens on, and
# the tests check the chDB query the hook writes to the log.
my $node = PostgreSQL::Test::Cluster->new('host-credentials');
$node->init;
$node->append_conf(
    'postgresql.conf',
    qq{shared_preload_libraries = 'chdb_hook'\nlog_min_messages = DEBUG1},
);
$node->start;
END { $node->stop('fast') }

$node->safe_psql(postgres => q{
    CREATE ROLE cloud_users;
    CREATE ROLE other_users;
    CREATE ROLE member IN ROLE cloud_users;
    CREATE ROLE outsider;
    CREATE TABLE stuff (id int);
    GRANT ALL ON stuff TO member, outsider;
});

my $port     = PostgreSQL::Test::Cluster::get_free_port;
my $url      = "s3://localhost:$port/bucket/file.csv";
my $role_arn = 'arn:aws:iam::123456789012:role/path/loader';
my $nosign   = qr[\QSELECT * FROM s3({url:String}, NOSIGN, {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000];
my $signed   = qr[\QSELECT * FROM s3({url:String}, {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000];
my $assumed  = qr[\QSELECT * FROM s3({url:String}, extra_credentials(role_arn = '\E$role_arn\Q'), {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000];
my $params   = qr[\Q{ url: "\E$url\Q", format: "auto", structure: "id Nullable(Int32)" }];
my $failed   = qr/chdb: error executing chDB query/;

# Run a statement as a role and return the error, if any.
sub error_as {
    my ($role, $sql) = @_;
    my ($ret, $out, $err) = $node->psql(postgres => "SET ROLE $role; $sql");
    return $err;
}

sub allow {
    my $roles = shift;
    $node->safe_psql(postgres => "ALTER SYSTEM SET chdb_hook.host_credentials_roles = $roles");
    $node->reload;
}

subtest 'disabled by default' => sub {
    is $node->safe_psql(postgres => 'SHOW chdb_hook.host_credentials_roles'), '',
        'Should name no roles';
    check_query(
        $node, 'member while disabled',
        qq{SET ROLE member; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
    like error_as(member => qq{COPY stuff FROM '$url' (role_arn '$role_arn')}),
        qr/permission denied to use option "role_arn"/,
        'Should refuse role_arn while disabled';
};

subtest 'only superusers may name the roles' => sub {
    for my $role (qw(member outsider)) {
        like error_as($role => q{SET chdb_hook.host_credentials_roles = 'outsider'}),
            qr/permission denied to set parameter "chdb_hook.host_credentials_roles"/,
            "Should not let $role set the roles";
    }
};

subtest 'members use host credentials' => sub {
    allow q{'other_users, cloud_users'};
    check_query(
        $node, 'member',
        qq{SET ROLE member; COPY stuff FROM '$url'},
        $failed, $signed, $params,
    );
    check_query(
        $node, 'outsider',
        qq{SET ROLE outsider; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
    check_query(
        $node, 'member with keys',
        qq{SET ROLE member; COPY stuff FROM '$url' (access_key 'key', access_secret 'secret')},
        $failed,
        qr[\QSELECT * FROM s3({url:String}, {access_key:String}, {access_secret:String}, {format:String}, {structure:String})],
        qr[\Qaccess_key: "key", access_secret: "secret"],
    );
    check_query(
        $node, 'member with a GCS URL',
        qq{SET ROLE member; COPY stuff FROM 'gs://localhost:$port/bucket/file.csv'},
        $failed,
        qr[\QSELECT * FROM gcs({url:String}, NOSIGN, {format:String}, {structure:String})],
        qr[\Qformat: "auto"],
    );
};

subtest 'a role that does not exist allows no one' => sub {
    allow q{'no_such_role'};
    check_query(
        $node, 'member of another role',
        qq{SET ROLE member; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
};

subtest 'role_arn' => sub {
    allow q{'cloud_users'};
    check_query(
        $node, 'option',
        qq{SET ROLE member; COPY stuff FROM '$url' (role_arn '$role_arn')},
        $failed, $assumed, $params,
    );
    check_query(
        $node, 'setting',
        qq{SET ROLE member; SET chdb_hook.s3_role_arn = '$role_arn'; COPY stuff FROM '$url'},
        $failed, $assumed, $params,
    );
    check_query(
        $node, 'option over setting',
        qq{SET ROLE member; SET chdb_hook.s3_role_arn = 'arn:aws:iam::123456789012:role/other';
           COPY stuff FROM '$url' (role_arn '$role_arn')},
        $failed, $assumed, $params,
    );
    check_query(
        $node, 'setting of an outsider',
        qq{SET ROLE outsider; SET chdb_hook.s3_role_arn = '$role_arn'; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
    check_query(
        $node, 'COPY TO',
        qq{SET ROLE member; COPY stuff TO '$url' (role_arn '$role_arn')},
        qr/^$|chdb: error executing chDB query/,
        qr[\QINSERT INTO FUNCTION s3({url:String}, extra_credentials(role_arn = '\E$role_arn\Q'), {format:String}, {structure:String}) SETTINGS s3_truncate_on_insert = 1, s3_request_timeout_ms = 30000],
        $params,
    );

    like error_as(outsider => qq{COPY stuff FROM '$url' (role_arn '$role_arn')}),
        qr/permission denied to use option "role_arn"/,
        'Should refuse role_arn from an outsider';

    for my $bad (
        q{x') SETTINGS s3_request_timeout_ms = 1 --},
        'arn:aws:iam::123456789012:user/loader',
        'arn:aws:iam::12345:role/loader',
        'arn:aws:iam::123456789012:role/',
        q{arn:aws:iam::123456789012:role/it's},
        'arn:aws:s3:::bucket',
    ) {
        (my $quoted = $bad) =~ s/'/''/g;
        like error_as(member => qq{COPY stuff FROM '$url' (role_arn '$quoted')}),
            qr/is not an AWS IAM role ARN/, "Should refuse role_arn $bad";
    }
    like error_as(member => qq{SET chdb_hook.s3_role_arn = 'nope'; COPY stuff FROM '$url'}),
        qr/"nope" is not an AWS IAM role ARN/, 'Should refuse a setting that is not an ARN';

    for my $partition (qw(aws aws-cn aws-us-gov)) {
        my $arn = "arn:$partition:iam::123456789012:role/loader";
        check_query(
            $node, "partition $partition",
            qq{SET ROLE member; COPY stuff FROM '$url' (role_arn '$arn')},
            $failed, qr[\Qextra_credentials(role_arn = '\E$arn\Q')], $params,
        );
    }

    like error_as(member => qq{COPY stuff FROM '$url' (role_arn '$role_arn', access_key 'k', access_secret 's')}),
        qr/option "role_arn" requires an S3 URL and no "access_key"/,
        'Should refuse role_arn with keys';
    like error_as(member => qq{COPY stuff FROM 'http://localhost:$port/file.csv' (role_arn '$role_arn')}),
        qr/option "role_arn" requires an S3 URL and no "access_key"/,
        'Should refuse role_arn with an HTTP URL';
    like error_as(member => qq{COPY stuff FROM 'gs://localhost:$port/bucket/file.csv' (role_arn '$role_arn')}),
        qr/option "role_arn" requires an S3 URL and no "access_key"/,
        'Should refuse role_arn with a GCS URL';
};

done_testing;
