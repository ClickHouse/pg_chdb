package chDBTestUtils;

use strict;
use warnings;
use Exporter 'import';
use PostgreSQL::Test::Utils;
use Test::More;

our @EXPORT = qw(bgw_log check_log check_query);

=begin chdb_bgw

Fetch chdb_bgw log lines since the last fetch.

=cut

{
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

=head2 check_log

Compare hdb_bgw log lines immediately following a "executing chDB query" log
line. The first should contain the chDB query with placeholders. The second
should map the placeholders to values.

=cut

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

=head2 check_query

Run a subtest to validate that a given query's log values containing the
resulting chDB query and associated parameters.

=cut

sub check_query {
    my ($node, $desc, $query, $err_rx, @args) = @_;
    subtest $desc => sub {
        eval { $node->safe_psql(postgres => $query) };
        like $@, $err_rx, "Should have $desc chDB error";
        check_log $node, $desc, @args;
    };
}

1;
