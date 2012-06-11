#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 20;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};

use t::Utils;
rebuild_tfiles();

use Ubic;

local_ubic;

# single (5*3 = 15)
{
    my $result;

    for (qw(/etc/init.d/sleeping-daemon /etc/rc.d/init.d/sleeping-daemon /etc/rc3.d/S98sleeping-daemon)) {
        local $ENV{INIT_SCRIPT_NAME} = $_;

        $result = qx($perl t/bin/any-init start);
        like($result, qr/^\QStarting sleeping-daemon... started (pid \E\d+\)$/);

        $result = qx($perl t/bin/any-init status);
        like($result, qr/sleeping-daemon \s+ running/x, 'Ubic::Run works, sleeping-daemon is running');

        use Test::Exception;
        dies_ok(sub { xsystem("$perl t/bin/any-init blah 2>>tfiles/blah.stderr") }, "Ubic::Run dies encountering an unknown command");
        lives_ok(sub { xsystem("$perl t/bin/any-init logrotate") }, "logrotate command implemented"); #FIXME: better fix logrotate configs!

        $result = qx($perl t/bin/any-init stop);

        $result = qx($perl t/bin/any-init status);
        like($result, qr/sleeping-daemon \s+ off/x, 'Ubic::Run works, sleeping-daemon is off');
    }
}

# invalid filename (1)
{
    local $ENV{INIT_SCRIPT_NAME} = '/usr/bin/sleeping-daemon';
    my $result = qx($perl t/bin/any-init start 2>&1 >/dev/null);
    like($result, qr{^Strange \$0: /usr/bin/sleeping-daemon}, 'Ubic::Run throws exception when script name is unknown');
}

# multi (2)
{
    my $result = qx($perl t/bin/multi-init status sleep1);
    like($result, qr/multi.sleep1 \s+ off/x, 'status works for multiservice');
    $result = qx($perl t/bin/multi-init start sleep1 sleep2);
    like($result, qr/
    Starting \s+ multi\.sleep1\.\.\. \s+ started \s+ \(pid \s+ \d+\)\s+
    Starting \s+ multi\.sleep2\.\.\. \s+ started \s+ \(pid \s+ \d+\)
    /msx, 'status works for multiservice');
}

# explicit service name (2)
{
    my $result = qx($perl t/bin/explicit-init start);
    like($result, qr/^\QStarting sleeping-daemon... started (pid \E\d+\)$/, 'start init script with explicit service name');

    $result = qx($perl t/bin/explicit-init stop);

    $result = qx($perl t/bin/explicit-init status);
    like($result, qr/sleeping-daemon \s+ off/x, 'status of init script with explicit service name');
}
