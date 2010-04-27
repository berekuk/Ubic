#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2;

use lib 'lib';

use Perl6::Slurp;
use t::Utils;
rebuild_tfiles();

use Ubic;
Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');

{
    for (1..10_000) {
        my $status = Ubic->cached_status('multi-impl.abc');
    }

    my $stat = slurp("/proc/$$/statm");
    my ($mem) = $stat =~ /^(\d+)/;
    cmp_ok($mem, '<', 15_000);
}

{
    for (1..10_000) {
        eval {
            my $status = Ubic->cached_status('multi-impl.broken.blah');
        };
    }

    my $stat = slurp("/proc/$$/statm");
    my ($mem) = $stat =~ /^(\d+)/;
    cmp_ok($mem, '<', 15_000);
}
