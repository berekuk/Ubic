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

sub force :Test(4) {
    system("$perl bin/ubic stop >>tfiles/log 2>>tfiles/err.log");
    ok $?, 'stop without --force - non-zero exit code';
    is
        slurp('tfiles/err.log'),
        "Use --force option if you want to stop all services\n",
        'error message when stopping root service without --force';
    xsystem('rm tfiles/*log');

    system("$perl bin/ubic stop multi-impl >>tfiles/log 2>>tfiles/err.log");
    ok $?, 'stop multi-impl without --force - non-zero exit code';
    is
        slurp('tfiles/err.log'),
        "Use --force option if you want to stop all multi-impl services\n",
        'error message when stopping multi-impl service without --force';
}

# most of script tests are in t/cmd.t, implemented as Ubic::Cmd tests

__PACKAGE__->new->runtests;
