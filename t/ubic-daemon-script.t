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

sub start_list_stop :Test(8) {
    system("$perl bin/ubic-daemon --name=blah 'sleep 100' >>tfiles/log 2>>tfiles/err.log");
    ok -e "tfiles/ubic/ubic-daemon/blah", 'pid file created';
    is slurp('tfiles/log'), '', 'stdout is empty';
    is slurp('tfiles/err.log'), '', 'stderr is empty';

    system("$perl bin/ubic-daemon --list >>tfiles/list.log 2>>tfiles/list.err.log");
    is slurp('tfiles/list.log'), "blah\trunning\n", '--list stdout contains the list of daemons';
    is slurp('tfiles/list.err.log'), '', '--list stderr is empty';

    system("$perl bin/ubic-daemon --stop --name=blah >>tfiles/stop.log 2>>tfiles/stop.err.log");
    ok not(-e "tfiles/ubic/ubic-daemon/blah"), 'stop removes pidfile';
    is slurp('tfiles/stop.log'), '', 'stdout is empty';
    is slurp('tfiles/stop.err.log'), '', 'stderr is empty';
}

__PACKAGE__->new->runtests;
