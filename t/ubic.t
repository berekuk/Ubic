#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4 + 4 + 4 + 4;
use Test::Exception;

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

# services() method - also check that service_dir works, so these tests are first (4)
{
    my @services = Ubic->services;
    is(scalar(@services), 3, 'all services returned by services() method');

    @services = sort { $a->name cmp $b->name } @services;

    is($services[0]->name, 'multi', 'first service is multi');
    is($services[1]->name, 'sleeping-daemon', 'second service is sleeping-daemon');
    is($services[2]->name, 'sleeping-daemon2', 'third service is sleeping-daemon2');
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

# multiservices (4)
{
    lives_ok(sub { Ubic->service('multi')->service('sleep2') }, 'multi/sleep2 is accessible');
    dies_ok(sub { Ubic->service('multi')->service('sleep3') }, 'multi/sleep3 is non-existent');
    lives_ok(sub { Ubic->service('multi/sleep2') }, 'multi/sleep2 is accessible through short syntax too');
    dies_ok(sub { Ubic->service('multi/sleep3') }, 'multi/sleep3 is non-existent with short syntax either');
}

# TODO - test reload, try_restart, force_reload
# TODO - test locks
# TODO - test cached_status

