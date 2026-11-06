#!/usr/bin/perl
use strict;
use warnings;
use Try::Tiny;
use List::MoreUtils qw(natatime);

{ package TestLogger; sub warn {} }
{ package TestError; sub type { $_[0]{type} } }
{ package Koha::Exceptions::Elasticsearch::BadResponse; our @ISA = ('TestError') }
{ package TestJSON; sub decode { return {record_server => 'biblioserver', record_ids => [1]} } }
{ package TestJob;
  sub new { bless { id => $_[1], status => 'new' }, $_[0] }
  sub id { $_[0]{id} } sub status { $_[0]{status} = $_[1] if @_ > 1; $_[0]{status} }
  sub data { '{}' } sub json { bless {}, 'TestJSON' } sub store { $_[0] }
}
{ package TestJobs; sub update { my ($self, $values) = @_; for my $job (@{$self->{jobs}}) { $job->{$_} = $values->{$_} for keys %$values } } }
{ package Koha::BackgroundJobs;
  our %jobs;
  sub search { my ($class, $query) = @_; return bless {jobs => [map { $jobs{$_} } @{$query->{id}}]}, 'TestJobs' }
}
{ package TestIndexer;
  our @outcomes;
  sub update_index { my $outcome = shift @outcomes; die $outcome if ref($outcome) || ($outcome // '') ne 'ok' }
}
{ package Koha::SearchEngine::Indexer; sub new { bless {}, 'TestIndexer' } }

my $logger = bless {}, 'TestLogger';
my $biblio_indexer = bless {}, 'TestIndexer';
my $auth_indexer = bless {}, 'TestIndexer';
my $at_a_time = 5000;
open my $fh, '<', $ARGV[0] or die $!;
local $/;
my $source = <$fh>;
$source =~ /(sub commit \{.*)\z/s or die "commit function not found\n";
eval $1;
die $@ if $@;
my $job = TestJob->new(1);
$Koha::BackgroundJobs::jobs{1} = $job;
my $no_nodes = bless {type => 'NoNodes'}, 'Koha::Exceptions::Elasticsearch::BadResponse';
for (1..2) {
    @TestIndexer::outcomes = ($no_nodes);
    my ($complete) = commit($job);
    die "outage did not retain job\n" if $complete || $job->status ne 'new';
}
@TestIndexer::outcomes = ('ok');
my ($complete) = commit($job);
die "recovery failed\n" unless $complete && $job->status eq 'finished';
$job->status('new');
@TestIndexer::outcomes = (bless {type => 'BadRequest'}, 'Koha::Exceptions::Elasticsearch::BadResponse');
($complete) = commit($job);
die "non-transient error was not failed\n" unless $complete && $job->status eq 'failed';
print "PASS: repeated NoNodes, recovery, and permanent indexing error\n";
