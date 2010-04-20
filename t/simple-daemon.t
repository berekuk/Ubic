#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;

use lib 'lib';

use Time::HiRes qw(sleep);
use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Service::SimpleDaemon;

my $service = Ubic::Service::SimpleDaemon->new({
    name => 'simple1',
    bin => q{perl -e 'use IO::Handle; print "stdout\n"; print STDERR "stderr\n"; STDOUT->flush; STDERR->flush; sleep 1000'},
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

is(xqx('cat tfiles/stdout'), "stdout\n", 'daemon stdout');
is(xqx('cat tfiles/stderr'), "stderr\n", 'daemon stderr');

