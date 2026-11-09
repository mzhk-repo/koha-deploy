#!/usr/bin/perl
use strict;
use warnings;
use File::Temp;
use IO::Socket::INET;
BEGIN {
    my ($fh, $path) = File::Temp::tempfile(UNLINK => 1);
    print $fh '<yazgfs><config><database>test</database><hostname>localhost</hostname><pluginsdir>/tmp</pluginsdir></config></yazgfs>';
    close $fh;
    $ENV{KOHA_CONF} = $path;
}
use Koha::SearchEngine::Elasticsearch;

open my $fh, '<', $ARGV[0] or die $!;
my $source = do { local $/; <$fh> };
$source =~ /(sub scope_product_check \{.*)\z/s or die "product check fix not found\n";
eval $1;
die $@ if $@;
scope_product_check();

for (1 .. 3) {
    my $client = Search::Elasticsearch->new(nodes => ['http://localhost:9200']);
    my $cxn = $client->transport->cxn_pool->cxns->[0];
    for my $status (599, 503, 401) {
        eval { $cxn->process_response({method => 'HEAD'}, $status, 'Unavailable', '', {}) };
        die "error response was accepted\n" unless $@;
        die "error poisoned product check\n"
            unless $Search::Elasticsearch::Role::Cxn::PRODUCT_CHECK_VALUE eq 'Elasticsearch';
    }
    for my $headers ({'x-elastic-product' => 'Elasticsearch'}, {}) {
        eval { $cxn->process_response({method => 'HEAD'}, 200, 'OK', '', $headers) };
        die "compatible response rejected: $@\n" if $@;
        die "compatibility hook leaked outside response\n"
            unless $Search::Elasticsearch::Role::Cxn::PRODUCT_CHECK_VALUE eq 'Elasticsearch';
    }
    eval { $cxn->process_response({method => 'HEAD'}, 200, 'OK', '', {'x-elastic-product' => 'Other'}) };
    die "unexpected product accepted\n" unless ref($@) eq 'Search::Elasticsearch::Error::ProductCheck';
}
print "PASS: failed and headerless responses do not poison product checks; unexpected products remain rejected\n";

my $dir = File::Temp::tempdir(CLEANUP => 1);
my $server = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 5)
    or die "cannot start test HTTP server: $!\n";
my $port = $server->sockport;
my $pid = fork();
die "fork failed: $!\n" unless defined $pid;
if (!$pid) {
    while (my $socket = $server->accept) {
        my $request = <$socket> // '';
        while (my $line = <$socket>) { last if $line =~ /^\r?\n$/ }
        my $down = -e "$dir/down";
        my $body = $down ? '' : '{"version":{"number":"8.19.6"}}';
        print $socket $down ? "HTTP/1.1 503 Unavailable\r\n" : "HTTP/1.1 200 OK\r\nX-Elastic-Product: Elasticsearch\r\n";
        print $socket "Connection: close\r\nContent-Type: application/json\r\nContent-Length: ", length($body), "\r\n\r\n";
        print $socket $body unless $request =~ /^HEAD /;
        close $socket;
    }
    exit;
}
close $server;
END { local $?; if ($pid) { kill 'TERM', $pid; waitpid($pid, 0) } }
for (1 .. 2) {
    open my $down, '>', "$dir/down" or die $!;
    close $down;
    my $client = Search::Elasticsearch->new(nodes => ["http://127.0.0.1:$port"], handle_args => {proxy => undef});
    eval { $client->info };
    die "outage did not produce NoNodes\n" unless ref($@) eq 'Search::Elasticsearch::Error::NoNodes';
    unlink "$dir/down" or die $!;
    die "client did not recover after outage\n" unless $client->info->{version}{number} eq '8.19.6';
}
print "PASS: real HTTP client recovers from repeated headerless 503 outages in the same process\n";
