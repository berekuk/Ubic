#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;

use lib 'lib';

use Time::HiRes qw(sleep);

use t::Utils;
rebuild_tfiles();

BEGIN {
    $ENV{UBIC_DAEMON_PID_DIR} = 'tfiles';
}
use Ubic::Service::SimpleDaemon;

my $service = Ubic::Service::SimpleDaemon->new({
    name => 'simple1',
    bin => ['perl', '-e', 'use IO::Handle; $SIG{TERM} = sub { exit 0 }; print "stdout\n"; print STDERR "stderr\n"; STDOUT->flush; STDERR->flush; sleep 1000'],
    user => $ENV{LOGNAME},
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
});

is($service->status, 'not running', 'status before start');
$service->start;
is($service->status, 'running', 'start works');

sleep 1;

$service->stop;
is($service->status, 'not running', 'stop works');

is(slurp('tfiles/stdout'), "stdout\n", 'daemon stdout');
is(slurp('tfiles/stderr'), "stderr\n", 'daemon stderr');

