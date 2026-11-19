#!/usr/bin/perl

use v5.34;
use strict;
use warnings FATAL => 'all';
use IO::Socket::INET;
use POSIX ();
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use lib 't';
use chDBTestUtils;

# These tests need no cloud account, so nothing they run can succeed.
#
# COPY takes s3:// URLs, which chDB sends to AWS. Those name a bucket that does
# not exist, and the tests check the chDB query the hook wrote to the log: with
# NOSIGN for an anonymous request, without it to use the host credentials.
#
# chdb_query() can name any endpoint, so a local listener stands in for S3. It
# answers every request with 403 and records whether the request was signed.
my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Listen    => 16,
    ReuseAddr => 1,
) or die "Cannot listen: $!";
my $port     = $listener->sockport;
my $requests = PostgreSQL::Test::Utils::tempdir() . '/requests';

my $pid = fork // die "Cannot fork: $!";
if (!$pid) {
    # Leave without running the END blocks and the test plan of the parent.
    $SIG{TERM} = $SIG{INT} = sub { POSIX::_exit(0) };
    while (my $client = $listener->accept) {
        my $signed = 0;
        while (defined(my $line = <$client>)) {
            last if $line =~ /^\r?$/;
            $signed = 1 if $line =~ /^Authorization:\s*AWS4-HMAC-SHA256 Credential=([^\/]+)/i;
        }
        open my $fh, '>>', $requests or die "Cannot open $requests: $!";
        say {$fh} $signed ? 'signed' : 'anonymous';
        close $fh;
        print {$client} "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        close $client;
    }
    POSIX::_exit(0);
}
close $listener;

# Stand in for the cloud credentials of a host, where the server can find them.
# Disabling the instance metadata service keeps the tests off the network.
local $ENV{AWS_ACCESS_KEY_ID}         = 'HOSTKEY';
local $ENV{AWS_SECRET_ACCESS_KEY}     = 'hostsecret';
local $ENV{AWS_EC2_METADATA_DISABLED} = 'true';
delete local @ENV{qw(AWS_SESSION_TOKEN AWS_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE)};

my $node = PostgreSQL::Test::Cluster->new('host-credentials');
$node->init;
$node->append_conf(
    'postgresql.conf',
    qq{shared_preload_libraries = 'chdb, chdb_hook'\nlog_min_messages = DEBUG1},
);
$node->start;
END {
    $node->stop('fast') if $node;
    kill TERM => $pid if $pid;
}

$node->safe_psql(postgres => q{
    CREATE EXTENSION chdb;
    CREATE ROLE cloud_users;
    CREATE ROLE "S3 Users";
    CREATE ROLE other_users;
    CREATE ROLE member IN ROLE cloud_users;
    CREATE ROLE "Quoted Member" IN ROLE "S3 Users";
    CREATE ROLE outsider;
    CREATE TABLE stuff (id int);
    GRANT ALL ON stuff TO member, "Quoted Member", outsider;
    GRANT EXECUTE ON FUNCTION chdb_query(text) TO member, "Quoted Member", outsider;
});

my $url    = "s3://localhost:$port/bucket/file.csv";
my $nosign = qr[\QSELECT * FROM s3({url:String}, NOSIGN, {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000];
my $signed = qr[\QSELECT * FROM s3({url:String}, {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000];
my $params = qr[\Q{ url: "\E$url\Q", format: "auto", structure: "id Nullable(Int32)" }];

# The role a member asks chDB to assume with the host credentials, and the
# query the hook then writes.
my $role_arn = 'arn:aws:iam::123456789012:role/path/loader';
my $assumed  = qr[\QSELECT * FROM s3({url:String}, extra_credentials(role_arn = '\E$role_arn\Q'), {format:String}, {structure:String}) SETTINGS s3_request_timeout_ms = 30000];

# No request can succeed (see above), so every COPY fails with this error.
my $failed = qr/chdb: error executing chDB query/;

# Return how the requests since the last call were made: signed, anonymous, a
# mix of the two, or none.
sub requests_were {
    my %seen;
    if (-e $requests) {
        $seen{$_} = 1 for split /\n/, slurp_file $requests;
        unlink $requests;
    }
    return join('+', sort keys %seen) || 'none';
}

# Set a host_credentials_roles GUC for the server.
sub allow {
    my ($guc, $roles) = @_;
    $node->safe_psql(postgres => "ALTER SYSTEM SET $guc.host_credentials_roles = $roles");
    $node->reload;
}

# Run a statement as a role and return the error it raised, if any.
sub error_as {
    my ($role, $sql) = @_;
    my ($ret, $out, $err) = $node->psql(postgres => "SET ROLE $role; $sql");
    return $err;
}

# Run chdb_query() against the listener as a role, without NOSIGN. It fails,
# as the listener refuses every request.
sub query_as {
    my $role = shift;
    $node->psql(
        postgres => qq{
            SET ROLE $role;
            SELECT * FROM chdb_query(
                \$\$SELECT * FROM s3('http://localhost:$port/bucket/file.csv', 'CSV', 'id Int32')\$\$
            ) AS (id int)
        }
    );
    # Skip the log of this query, so check_query() finds the one that follows.
    chDBTestUtils::server_log $node;
}

subtest 'disabled by default' => sub {
    for my $guc (qw(chdb chdb_hook)) {
        is $node->safe_psql(postgres => "SHOW $guc.host_credentials_roles"), '',
            "Should name no roles in $guc.host_credentials_roles";
    }
    check_query(
        $node, 'COPY',
        qq{SET ROLE member; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
    requests_were;
    query_as 'member';
    is requests_were, 'anonymous', 'Should send an anonymous chdb_query request';
};

subtest 'chdb_hook.host_credentials_roles' => sub {
    allow chdb_hook => q{'other_users, cloud_users, "S3 Users"'};

    check_query(
        $node, 'member without keys',
        qq{SET ROLE member; COPY stuff FROM '$url'},
        $failed, $signed, $params,
    );
    check_query(
        $node, 'member of a quoted role without keys',
        qq{SET ROLE "Quoted Member"; COPY stuff FROM '$url'},
        $failed, $signed, $params,
    );
    check_query(
        $node, 'outsider without keys',
        qq{SET ROLE outsider; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
    # Keys in the statement take the place of the host credentials.
    check_query(
        $node, 'member with keys',
        qq{SET ROLE member; COPY stuff FROM '$url' (access_key 'key', access_secret 'secret')},
        $failed,
        qr[\QSELECT * FROM s3({url:String}, {access_key:String}, {access_secret:String}, {format:String}, {structure:String})],
        qr[\Qaccess_key: "key", access_secret: "secret"],
    );

    # Only S3 URLs use host credentials.
    check_query(
        $node, 'member with a GCS URL',
        qq{SET ROLE member; COPY stuff FROM 'gs://localhost:$port/bucket/file.csv'},
        $failed,
        qr[\QSELECT * FROM gcs({url:String}, NOSIGN, {format:String}, {structure:String})],
        qr[\Qformat: "auto"],
    );

    # The setting of the hook does not reach chdb_query().
    requests_were;
    query_as 'member';
    is requests_were, 'anonymous', 'Should not apply to chdb_query';
};

subtest 'chdb.host_credentials_roles' => sub {
    allow chdb => q{'cloud_users, "S3 Users"'};
    requests_were;

    query_as 'member';
    is requests_were, 'signed', 'Should sign with the host credentials for a member';
    query_as '"Quoted Member"';
    is requests_were, 'signed',
        'Should sign with the host credentials for a member of a quoted role';
    query_as 'outsider';
    is requests_were, 'anonymous', 'Should send an anonymous request for an outsider';
};

subtest 'a role dropped after it was named allows none' => sub {
    $node->safe_psql(postgres => 'CREATE ROLE fleeting; GRANT fleeting TO outsider');
    allow chdb      => q{'fleeting'};
    allow chdb_hook => q{'fleeting'};
    requests_were;

    query_as 'outsider';
    is requests_were, 'signed', 'Should sign for a member of the role';

    $node->safe_psql(postgres => 'DROP ROLE fleeting');
    query_as 'outsider';
    is requests_were, 'anonymous', 'Should send an anonymous chdb_query request';
    check_query(
        $node, 'COPY',
        qq{SET ROLE outsider; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
};

subtest 'role_arn names a role to assume' => sub {
    allow chdb_hook => q{'cloud_users'};

    # A member names the role with the option or the setting. The requests
    # still fail (see above); the tests check the query in the log.
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
        $node, 'COPY TO',
        qq{SET ROLE member; COPY stuff TO '$url' (role_arn '$role_arn')},
        qr/^$|chdb: error executing chDB query/,
        qr[\QINSERT INTO FUNCTION s3({url:String}, extra_credentials(role_arn = '\E$role_arn\Q'), {format:String}, {structure:String}) SETTINGS s3_truncate_on_insert = 1, s3_request_timeout_ms = 30000],
        $params,
    );
    for my $partition (qw(aws-cn aws-us-gov)) {
        my $arn = "arn:$partition:iam::123456789012:role/loader";
        check_query(
            $node, "partition $partition",
            qq{SET ROLE member; COPY stuff FROM '$url' (role_arn '$arn')},
            $failed, qr[\Qextra_credentials(role_arn = '\E$arn\Q')], $params,
        );
    }

    # The setting changes nothing where host credentials are not used: for an
    # outsider, with keys, and for a URL that is not S3.
    check_query(
        $node, 'setting of an outsider',
        qq{SET ROLE outsider; SET chdb_hook.s3_role_arn = '$role_arn'; COPY stuff FROM '$url'},
        $failed, $nosign, $params,
    );
    check_query(
        $node, 'setting with keys',
        qq{SET ROLE member; SET chdb_hook.s3_role_arn = '$role_arn';
           COPY stuff FROM '$url' (access_key 'key', access_secret 'secret')},
        $failed,
        qr[\QSELECT * FROM s3({url:String}, {access_key:String}, {access_secret:String}, {format:String}, {structure:String})],
        qr[\Qaccess_key: "key", access_secret: "secret"],
    );
    check_query(
        $node, 'setting with a GCS URL',
        qq{SET ROLE member; SET chdb_hook.s3_role_arn = '$role_arn';
           COPY stuff FROM 'gs://localhost:$port/bucket/file.csv'},
        $failed,
        qr[\QSELECT * FROM gcs({url:String}, NOSIGN, {format:String}, {structure:String})],
        qr[\Qformat: "auto"],
    );

    # The hook raises these errors itself, before any request.
    like error_as(outsider => qq{COPY stuff FROM '$url' (role_arn '$role_arn')}),
        qr/permission denied to use option "role_arn"/,
        'Should refuse the option from an outsider';
    for my $bad (
        q{x') SETTINGS s3_request_timeout_ms = 1 --},
        q{arn:aws:iam::123456789012:role/it's},
        'arn:aws:iam::123456789012:user/loader',
        'arn:aws:iam::12345:role/loader',
        'arn:aws:iam::123456789012:role/',
        'arn:aws:s3:::bucket',
        '',
    ) {
        (my $quoted = $bad) =~ s/'/''/g;
        like error_as(member => qq{COPY stuff FROM '$url' (role_arn '$quoted')}),
            qr/argument to option "role_arn" must be an AWS IAM role ARN/,
            "Should refuse the option value '$bad'";
    }
    like error_as(
        member => qq{COPY stuff FROM '$url' (role_arn '$role_arn', access_key 'k', access_secret 's')}
    ), qr/option "role_arn" requires an S3 URL and no "access_key"/,
        'Should refuse the option with keys';
    for my $other ("http://localhost:$port/file.csv", "gs://localhost:$port/bucket/file.csv") {
        like error_as(member => qq{COPY stuff FROM '$other' (role_arn '$role_arn')}),
            qr/option "role_arn" requires an S3 URL and no "access_key"/,
            "Should refuse the option for $other";
    }
};

done_testing;
