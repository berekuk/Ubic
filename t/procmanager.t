#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Service::ProcManager;

my $service = Ubic::Service::ProcManager->new({
    pidfile => "tfiles/fastcgi.pid",
    socket => "tfiles/fastcgi.sock",
    child => 5,
    log => "tfiles/fastcgi-restart.log",
    bin => "t/bin/fastcgi.pl",
    user => $ENV{LOGNAME},
});

$service->start;
is($service->status, 'running', 'start works');

$service->stop;
is($service->status, 'not running', 'stop works');

# TODO - check more thoroughly start/stop return values and that fastcgi process is actually works


