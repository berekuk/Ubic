#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2;

use lib 'lib';

use PPB::Test::TFiles;
use Yandex::X qw(xqx);

use Ubic;
Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');

{
    for (1..10_000) {
        my $status = Ubic->cached_status('multi-impl.abc');
    }

    my $stat = xqx("cat /proc/$$/statm");
    my ($mem) = $stat =~ /^(\d+)/;
    cmp_ok($mem, '<', 15_000);
}

{
    for (1..10_000) {
        eval {
            my $status = Ubic->cached_status('multi-impl.broken.blah');
        };
    }

    my $stat = xqx("cat /proc/$$/statm");
    my ($mem) = $stat =~ /^(\d+)/;
    cmp_ok($mem, '<', 15_000);
}
