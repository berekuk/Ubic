#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

start_daemon({
    bin => "sleep 10",
    pidfile => "tfiles/pid",
});
ok(check_daemon("tfiles/pid"), 'daemon is running');

stop_daemon('tfiles/pid');
ok(!(check_daemon("tfiles/pid")), 'daemon is not running');

start_daemon({
    bin => "sleep 2",
    pidfile => "tfiles/pid",
});
ok(check_daemon("tfiles/pid"), 'daemon is running again');
sleep 4;
ok(!(check_daemon("tfiles/pid")), 'daemon stopped after several seconds');

