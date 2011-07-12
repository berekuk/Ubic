#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;

use Config;
my $perl = $Config{perlpath};

use t::Utils;
use Ubic::Daemon qw(:all);

use lib 'lib';

sub setup :Test(setup) {
    rebuild_tfiles();
    local_ubic({
        service_dirs => ['root_t/service'],
        default_user => 'root',
    });
    xsystem('chmod -R 777 tfiles');
}

sub watchdog :Tests(2) {
    Ubic->start('daemongroup-daemon');

    my $pid = check_daemon(Ubic->service('daemongroup-daemon')->pidfile)->pid;
    kill 15 => $pid;

    xsystem("$perl bin/ubic-watchdog >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");

    my @stat = stat("tfiles/ubic/status/daemongroup-daemon");

    is($stat[4], scalar(getpwnam('nobody')), 'status file owner is correct after watchdog');
    is($stat[5], scalar(getgrnam('daemon')), 'status file group is correct after watchdog');
}

__PACKAGE__->new->runtests;
