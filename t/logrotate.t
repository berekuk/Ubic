#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;
use Test::Fatal;

use lib 'lib';

use File::Copy qw(move);
use IO::Handle;
use Time::HiRes qw(sleep);

use t::Utils;

use Ubic;
use Ubic::Service::SimpleDaemon;

sub setup :Test(setup) {
    rebuild_tfiles;
    local_ubic;
}

sub logrotate :Tests(2) {
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use IO::Handle; use Time::HiRes qw(sleep); STDOUT->autoflush(1); $SIG{HUP} = "IGNORE"; for (1..100) {print "stdout: $_\n"; warn "stderr $_\n"; sleep 0.1;}'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
        reload_signal => 'HUP',
    });
    $service->start;
    sleep 1;
    move 'tfiles/stdout', 'tfiles/stdout2';
    move 'tfiles/stderr', 'tfiles/stderr2';
    sleep 1;
    $service->reload;
    sleep 2;
    $service->stop;
    ok((-s 'tfiles/stdout' and -s 'tfiles/stdout2'), 'stdout was reopened');
    ok((-s 'tfiles/stderr' and -s 'tfiles/stderr2'), 'stderr was reopened');
}

__PACKAGE__->new->runtests;
