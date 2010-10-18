#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;

use lib 'lib';

use t::Utils;
rebuild_tfiles();

use Ubic;
Ubic->set_data_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');

lives_ok(sub { my $lock = Ubic->lock('sleeping-daemon'); }, 'lock acuquired');
lives_ok(sub { my $lock = Ubic->lock('sleeping-daemon'); }, 'lock acuquired again');

{
    local $SIG{ALRM} = sub { die "alarm" };
    alarm(3);
    my $lock1 = Ubic->lock('sleeping-daemon');
    my $lock2 = Ubic->lock('sleeping-daemon');
    ok('one service can be locked twice from one process');
    alarm(0);
}

use Time::HiRes qw(time sleep alarm);
{
    my $started = time;
    if (my $pid = xfork) {
        sleep 0.1;
        my $lock = Ubic->lock('sleeping-daemon');
        my $period = time - $started;
        cmp_ok($period, '>', 0.8, 'lock after 1 second');
        cmp_ok($period, '<', 1.2, 'lock after 1 second');
        1 while wait > 0;
    }
    else {
        my $lock = Ubic->lock('sleeping-daemon');
        sleep 1;
    }
}
