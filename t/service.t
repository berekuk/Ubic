#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 7;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');
xsystem('mkdir tfiles/watchdog');
xsystem('mkdir tfiles/lock');

BEGIN {
    $ENV{UBIC_WATCHDOG_DIR} = 'tfiles/watchdog';
}

use Ubic::Service::Common;

my $running;
my $service = Ubic::Service::Common->new({
    start => sub {
        $running++;
    },
    stop => sub {
        $running--;
    },
    status => sub {
        if ($running) {
            return 'running';
        } else {
            return 'not running';
        }
    },
    name => 'some.service',
    lock_dir => 'tfiles/lock',
});
is($service->start, 'started', 'start works');
is($service->status, 'running', 'status after start');

is($service->stop, 'stopped', 'stop works');
is($service->status, 'not running', 'status after stop');

$service->start;
is($service->start, 'already running', 'double start');

is($service->stop, 'stopped', 'stop after double start');
is($service->stop, 'not running', 'double stop');

