#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};
$perl = "$perl -Mt::Utils::IgnoreWarn";

use t::Utils;

sub setup :Test(setup) {
    rebuild_tfiles;
    local_ubic;
}

sub unknown_command :Test(1) {
    system("$perl bin/ubic blah >>tfiles/log 2>>tfiles/err.log");
    is(slurp('tfiles/err.log'), "Unknown command 'blah'\n", 'unknown command error');
}

# most of script tests are in t/ubic.t, implemented as Ubic::Cmd tests

__PACKAGE__->new->runtests;
