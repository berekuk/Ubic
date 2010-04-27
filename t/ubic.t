#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2 + 4 + 4 + 6 + 1 + 1;
use Test::Exception;

use lib 'lib';

use t::Utils;
rebuild_tfiles();

use Ubic;
Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');

# services() method - also check that service_dir works, so these tests are first (2)
{
    my @services = Ubic->services;
    cmp_ok(scalar(@services), '>', 5, 'enough services returned by services() method');

    ok(scalar(grep { $_->name eq 'sleeping-daemon' } @services), 'sleeping-daemon is presented in services list');
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

# multiservices (6)
{
    lives_ok(sub { Ubic->service('multi')->service('sleep2') }, 'multi.sleep2 is accessible');
    dies_ok(sub { Ubic->service('multi')->service('sleep3') }, 'multi.sleep3 is non-existent');
    lives_ok(sub { Ubic->service('multi.sleep2') }, 'multi.sleep2 is accessible through short syntax too');
    dies_ok(sub { Ubic->service('multi.sleep3') }, 'multi.sleep3 is non-existent with short syntax either');

    Ubic->start('multi.sleep2');
    is(Ubic->service('multi.sleep2')->status, 'running', 'multiservice can be started too');
    Ubic->stop('multi.sleep2');
    is(Ubic->service('multi.sleep2')->status, 'not running', 'multiservice can be stopped');
}

# custom commands (1)
{
    is(Ubic->do_custom_command('sleeping-common', '2plus2'), 4, 'do_custom_command method works');
}

# user
{
    dies_ok(sub { Ubic->start('sleeping-daemon-root') }, "can't start root service"); # this forbids building from root
}

# TODO - test reload, try_restart, force_reload
# TODO - test locks
# TODO - test cached_status

