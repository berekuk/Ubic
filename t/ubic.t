#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 3 + 4 + 4;

use lib 'lib';

BEGIN {
    use Yandex::X;
    xsystem('rm -rf tfiles');
    xsystem('mkdir tfiles');
    xsystem('mkdir tfiles/watchdog');
    xsystem('mkdir tfiles/lock');
    xsystem('mkdir tfiles/pid');

    $ENV{UBIC_DAEMON_PID_DIR} = 'tfiles/pid';
}

use Ubic;

$Ubic::SINGLETON = Ubic->new({
    watchdog_dir => 'tfiles/watchdog',
    lock_dir => 'tfiles/lock',
    service_dir => 't/service',
});

# services() method - also check that service_dir works, so these tests are first (3)
{
    my @services = Ubic->services;
    is(scalar(@services), 2, 'both services returned by services() method');

    @services = sort { $a->name cmp $b->name } @services;

    is($services[0]->name, 'sleeping-daemon', 'first service is sleeping-daemon');
    is($services[1]->name, 'sleeping-daemon2', 'second service is sleeping-daemon2');
}

# is_enabled, enable, disable (4)
{
    ok(not(Ubic->is_enabled('sleeping-daemon')), 'sleeping-daemon is disabled');
    Ubic->enable('sleeping-daemon');
    ok(Ubic->is_enabled('sleeping-daemon'), 'sleeping-daemon is enabled now');
    ok(not(Ubic->is_enabled('sleeping-daemon2')), 'sleeping-daemon2 is still disabled');
    Ubic->disable('sleeping-daemon');
    ok(not(Ubic->is_enabled('sleeping-daemon')), 'sleeping-daemon is disabled again');
}

# start, stop, restart (4)
{
    Ubic->start('sleeping-daemon');
    ok(Ubic->is_enabled('sleeping-daemon'), 'sleeping-daemon is enabled after start');
    my $service = Ubic->service('sleeping-daemon');
    is($service->status, 'running', 'sleeping-daemon is running');

    Ubic->stop('sleeping-daemon');
    is($service->status, 'not running', 'sleeping-daemon is not running');
    ok(not(Ubic->is_enabled('sleeping-daemon')), 'sleeping-daemon is disabled after stop');
}

# TODO - test reload, try_restart, force_reload
# TODO - test locks
# TODO - test cached_status

