#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

start_daemon({
    bin => "sleep 10",
    pidfile => "tfiles/pid",
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
    ubic_log => 'tfiles/ubic.log',
});
ok(check_daemon("tfiles/pid"), 'daemon is running');
dies_ok(sub {
    start_daemon({
        bin => "sleep 10",
        pidfile => "tfiles/pid",
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
}, 'start_daemon fails if daemon is already started');

#diag("stop here\n");
#exit;

stop_daemon('tfiles/pid');
ok(!(check_daemon("tfiles/pid")), 'daemon is not running');

start_daemon({
    bin => "sleep 2",
    pidfile => "tfiles/pid",
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
    ubic_log => 'tfiles/ubic.log',
});
ok(check_daemon("tfiles/pid"), 'daemon is running again');
sleep 4;
ok(!(check_daemon("tfiles/pid")), 'daemon stopped after several seconds');



