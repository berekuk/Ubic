#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};

use t::Utils;
rebuild_tfiles();

use Ubic;
Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');

# single (4)
{
    my $result;

    $result = qx($perl t/bin/sleeping-init start);

    $result = qx($perl t/bin/sleeping-init status);
    like($result, qr/sleeping-daemon \s+ running/x, 'Ubic::Run works, sleeping-daemon is running');

    use Test::Exception;
    dies_ok(sub { xsystem("$perl t/bin/sleeping-init blah 2>>tfiles/blah.stderr") }, "Ubic::Run dies encountering an unknown command");
    lives_ok(sub { xsystem("$perl t/bin/sleeping-init logrotate") }, "logrotate command implemented"); #FIXME: better fix logrotate configs!

    $result = qx($perl t/bin/sleeping-init stop);

    $result = qx($perl t/bin/sleeping-init status);
    like($result, qr/sleeping-daemon \s+ off/x, 'Ubic::Run works, sleeping-daemon is off');
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

