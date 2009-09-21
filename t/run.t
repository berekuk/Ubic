#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;

use lib 'lib';

BEGIN {
    use Yandex::X;
    xsystem('rm -rf tfiles');
    xsystem('mkdir tfiles');
    xsystem('mkdir tfiles/watchdog');
    xsystem('mkdir tfiles/lock');
    xsystem('mkdir tfiles/pid');

    $ENV{UBIC_DAEMON_PID_DIR} = 'tfiles/pid';
    $ENV{UBIC_WATCHDOG_DIR} = 'tfiles/watchdog';
    $ENV{UBIC_LOCK_DIR} = 'tfiles/lock';
    $ENV{UBIC_SERVICE_DIR} = 't/service';
    $ENV{PERL5LIB} = 'lib';
}

use Ubic;

{
    my $result;

    $result = qx(t/bin/sleeping-init start);

    $result = qx(t/bin/sleeping-init status);
    like($result, qr/sleeping-daemon \s+ running/x, 'Ubic::Run works, sleeping-daemon is running');

    use Test::Exception;
    dies_ok(sub { xsystem("t/bin/sleeping-init blah") }, "Ubic::Run dies encountering an unknown command");
    lives_ok(sub { xsystem("t/bin/sleeping-init logrotate") }, "logrotate command implemented"); #FIXME: better fix logrotate configs!

    $result = qx(t/bin/sleeping-init stop);

    $result = qx(t/bin/sleeping-init status);
    like($result, qr/sleeping-daemon \s+ off/x, 'Ubic::Run works, sleeping-daemon is off');
}

