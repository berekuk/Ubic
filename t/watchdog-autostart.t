#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};
$perl = "$perl -Mt::Utils::IgnoreWarn";

use Ubic;
use Ubic::Watchdog;
use t::Utils;

my $ignore_warn = ignore_warn(qr/Can't construct 'broken': failed/);

sub setup :Test(setup) {
    rebuild_tfiles;
    local_ubic(service_dirs => ['t/service/autostart']);
}

sub enable_disable :Test(2) {
    ok(Ubic->is_enabled('sleeping-daemon-autostart'), 'autostart service is initially enabled');
    Ubic->disable('sleeping-daemon-autostart');
    ok(not(Ubic->is_enabled('sleeping-daemon-autostart')), 'sleeping-daemon-autostart is explicitely disabled');
}

sub autostart :Test(2) {
    is(Ubic->cached_status('sleeping-daemon-autostart')->status, "autostarting");
    xsystem("$perl bin/ubic-watchdog >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is(Ubic->service('sleeping-daemon-autostart')->status->status, "running");
}

__PACKAGE__->new->runtests;
