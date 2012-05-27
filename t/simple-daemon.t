#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 23;

use lib 'lib';

use Time::HiRes qw(sleep);
use IO::Handle;

use t::Utils;

use Ubic;
use Ubic::Service::SimpleDaemon;

{
    rebuild_tfiles;
    local_ubic;

    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use IO::Handle; $SIG{TERM} = sub { exit 0 }; print "stdout\n"; print STDERR "stderr\n"; STDOUT->flush; STDERR->flush; sleep 1000'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
    });

    is($service->status, 'not running', 'status before start');
    $service->start;
    like($service->status, qr/^running \(pid \d+\)$/, 'start works');

    sleep 1;

    $service->stop;
    is($service->status, 'not running', 'stop works');

    is(slurp('tfiles/stdout'), "stdout\n", 'daemon stdout');
    is(slurp('tfiles/stderr'), "stderr\n", 'daemon stderr');
}

# cwd
{
    rebuild_tfiles;
    local_ubic;

    use Cwd;
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use Cwd; use IO::Handle; print getcwd."\n"; STDOUT->flush; sleep 1000'],
        stdout => getcwd.'/tfiles/stdout',
        stderr => getcwd.'/tfiles/stderr',
        cwd => 'tfiles',
    });

    unlike(getcwd, qr/tfiles$/, 'original dir is not tfiles');

    $service->start;
    like($service->status, qr/^running \(pid \d+\)$/, 'start works');

    unlike(getcwd, qr/tfiles$/, 'dir is still not tfiles after service start');

    sleep 1;

    $service->stop;
    is($service->status, 'not running', 'stop works');

    like(slurp('tfiles/stdout'), qr/tfiles$/, 'daemon started with correct cwd');
}

# env
{
    rebuild_tfiles;
    local_ubic;

    local $ENV{BAR} = 123;
    local $ENV{XXX} = 666;
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use Cwd; use IO::Handle; print "FOO: $ENV{FOO}\n"; print "BAR: $ENV{BAR}\n"; print "XXX: $ENV{XXX}\n"; STDOUT->flush; sleep 1000'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        env => {
            'FOO' => 5,
            'BAR' => 6,
        }
    });

    $service->start;
    like($service->status, qr/^running \(pid \d+\)$/, 'start works');

    is($ENV{FOO}, undef, 'env is not affected');
    is($ENV{BAR}, 123, 'env is not affected');

    sleep 1;

    $service->stop;
    is($service->status, 'not running', 'stop works');

    my @lines = split /\n/, slurp 'tfiles/stdout';
    is($lines[0], "FOO: 5", 'FOO set in service');
    is($lines[1], "BAR: 6", 'BAR overridden in service');
    is($lines[2], "XXX: 666", 'XXX unaffected in service');
}

# reload
{
    rebuild_tfiles;
    local_ubic;

    my $result;

    my $reloadless_service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'sleep 100'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
    });

    $result = $reloadless_service->reload;
    is($result->msg, 'not implemented');

    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'simple1',
        bin => ['perl', '-e', 'use IO::Handle; STDOUT->autoflush(1); $SIG{HUP} = sub { print "hup\n" }; sleep 100 for 1..10'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
        reload_signal => 'HUP',
    });

    $result = $service->reload;
    is($result->status, 'not running', 'reload while not running');

    $service->start;

    sleep 1; # let the code load and set sighub handler

    $result = $service->reload;
    is($result->action, 'reloaded', 'reload successful');
    like($result->msg, qr/^sent HUP to \d+$/, 'reload result message');

    sleep 1; # wait while code handles the first exception

    $result = $service->reload;
    is($result->action, 'reloaded', 'reload successful one more time');

    sleep 1;

    $service->stop;

    is(slurp('tfiles/stdout'), "hup\nhup\n", 'two sighups sent');
}
