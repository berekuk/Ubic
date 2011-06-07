#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 13;

use lib 'lib';

use Time::HiRes qw(sleep);

use t::Utils;
rebuild_tfiles();

use Ubic;
use Ubic::Service::SimpleDaemon;

local_ubic;

{
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use IO::Handle; print "stdout\n"; print STDERR "stderr\n"; STDOUT->flush; STDERR->flush; sleep 1000'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });

    is($service->status, 'not running', 'status before start');
    $service->start;
    like($service->status, qr/^running \(pid \d+\)$/, 'start works');

    sleep 1;

    $service->stop;
    is($service->status, 'not running', 'stop works');

    is(slurp('tfiles/stdout'), "stdout\n", 'daemon stdout');
    is(slurp('tfiles/stderr'), "stderr\n", 'daemon stderr');
}

{
    xsystem('rm', 'tfiles/stdout', 'tfiles/stderr', 'tfiles/ubic.log');
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use IO::Handle; $SIG{TERM} = sub { sleep 1; print "term\n"; STDOUT->flush; exit }; sleep 1000'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
        term_timeout => 2,
    });

    $service->start;
    sleep 1;
    $service->stop;

    is($service->status, 'not running', 'daemon stopped');

    is(slurp('tfiles/stdout'), "term\n", 'process terminated via sigterm');

    my $ubic_log = slurp('tfiles/ubic.log');
    like($ubic_log, qr/sending SIGTERM/, 'guaridan sent sigterm');
}

{
    xsystem('rm', 'tfiles/stdout', 'tfiles/stderr', 'tfiles/ubic.log');
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use IO::Handle; $SIG{TERM} = sub { sleep 3; print "term\n"; STDOUT->flush; exit }; sleep 1000'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
        term_timeout => 2,
    });

    $service->start;
    sleep 1;
    $service->stop;

    is($service->status, 'not running', 'daemon stopped');

    is(slurp('tfiles/stdout'), "", 'process terminated via sigkill');

    my $ubic_log = slurp('tfiles/ubic.log');
    like($ubic_log, qr/sending SIGTERM/, 'log - guaridan sent sigterm');
    like($ubic_log, qr/SIGTERM timeouted/, 'log - sigterm timeouted');
    like($ubic_log, qr/sending SIGKILL/, 'log - guardian sent sigkill');
}
