#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 17;

use lib 'lib';

use Time::HiRes qw(sleep);

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
        bin => ['perl', '-e', 'use Cwd; print getcwd."\n"; STDOUT->flush; sleep 1000'],
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
        bin => ['perl', '-e', 'use Cwd; print "FOO: $ENV{FOO}\n"; print "BAR: $ENV{BAR}\n"; print "XXX: $ENV{XXX}\n"; STDOUT->flush; sleep 1000'],
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
