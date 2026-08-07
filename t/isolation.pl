#!/usr/bin/perl

# chDB runs in a process the postmaster never registered, so killing it must
# cost one COPY and nothing else. A process holding Postgres shared memory
# killed the same way would take every backend down with it and force crash
# recovery.

use v5.34;
use strict;
use warnings FATAL => 'all';
use IPC::Run qw(start);
use POSIX qw(_exit);
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

plan skip_all => 'needs POSIX signals' if $^O eq 'MSWin32';

# Start a mock helper serve implemented by serve() below to test against.
my $port = PostgreSQL::Test::Cluster::get_free_port;
my $server = fork;
serve($port) unless $server;
END { kill 'KILL', $server if $server }

my $node = PostgreSQL::Test::Cluster->new('isolation');
$node->init;
$node->append_conf(
    'postgresql.conf',
    qq{shared_preload_libraries = 'chdb'\nlog_min_messages = DEBUG1}
);
$node->start;
END { $node->stop('fast') if $node }

$node->safe_psql(postgres => 'CREATE EXTENSION chdb');
$node->safe_psql(postgres => 'CREATE TABLE landing (id bigint, payload text)');

for my $signal (qw(SEGV ABRT KILL)) {
    subtest "helper killed by SIG$signal" => sub {
        my $offset = -s $node->logfile;
        my ($out, $err) = ('', '');
        my $copy = start [
            'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-d', $node->connstr('postgres'),
            '-c', "COPY landing FROM 'http://127.0.0.1:$port/data.csv'"
                . " (format 'CSV', timeout 60000)"
        ], \undef, \$out, \$err;

        my $helper = helper_pid($node, $offset);
        ok $helper, "Should find the helper process" or do {
            $copy->finish;
            return;
        };

        is kill($signal, $helper), 1, "Should signal the helper";
        $copy->finish;
        like $err, qr/\Qchdb: chDB was terminated by signal\E/,
            "Should fail the COPY with the helper's death";
        ok $node->log_contains(
            qr/ERROR:\s+chdb: chDB was terminated by signal \d+/, $offset),
            "Should log the helper's death";
        ok $node->log_contains(qr/CONTEXT:\s+query: SELECT \* FROM url\(/, $offset),
            "Should log the query that died with it";
        is $node->safe_psql(postgres => 'SELECT count(*) FROM landing'), 0,
            "Should leave no rows behind";
        is $node->safe_psql(postgres => 'SELECT pg_is_in_recovery()'), 'f',
            "Should leave the instance out of recovery";
        unlike slurp_file($node->logfile),
            qr/terminating any other active server processes/,
            "Should not have restarted the instance";
    };
}

done_testing;

# The backend logs the pid at DEBUG1 as soon as it forks the helper.
sub helper_pid {
    my ($node, $offset) = @_;
    my $logged = qr/chdb: chdb_helper pid (\d+)/;

    eval { $node->wait_for_log($logged, $offset) } or return undef;

    return slurp_file($node->logfile, $offset) =~ $logged ? $1 : undef;
}

# A CSV that arrives a row at a time, so the copy is still open to be broken.
sub serve {
    my $port = shift;
    require IO::Socket::INET;
    $SIG{PIPE} = 'IGNORE';
    my $server = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1', LocalPort => $port,
        Listen    => 5,           ReuseAddr => 1, Proto => 'tcp',
    ) or _exit(1);

    while (my $client = $server->accept) {
        my $head = 0;
        while (my $line = <$client>) {
            $head = 1 if $line =~ /^HEAD/;
            last if $line =~ /^\r?$/;
        }
        print $client "HTTP/1.1 200 OK\r\n"
            . "Content-Type: text/csv\r\nConnection: close\r\n\r\n";
        unless ($head) {
            for my $i (1 .. 600) {
                print $client "$i,row $i\n";
                $client->flush;
                # Use select to sleep for 50ms.
                select undef, undef, undef, 0.05;
            }
        }
        close $client;
    }
    _exit(0);
}
