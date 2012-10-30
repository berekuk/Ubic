#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;
use Test::Fatal;

use lib 'lib';

use Time::HiRes qw(sleep);
use IO::Handle;

use t::Utils;

use Ubic;
use Ubic::Service::SimpleDaemon;

sub setup :Test(setup) {
    rebuild_tfiles;
    local_ubic;
}

sub basic :Tests(5) {
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

sub test_cwd :Tests(5) {
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

sub env :Tests(7) {
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

sub reload :Tests(6) {
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

sub ulimit :Tests(4) {
    eval "require BSD::Resource"; # TODO - test only if BSD::Resource is installed?
    if ($@) {
        return 'BSD::Resource is not installed, skip ulimit tests';
    }
    my $service = Ubic::Service::SimpleDaemon->new({
        name => 'limited_service',
        bin => ['perl', '-e', 'system(q{bash -c "ulimit -n"}); sleep 5'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ulimit => {
            RLIMIT_NOFILE => 100,
        },
    });

    $service->start;
    is $service->status->status, 'running', 'started successfully';

    sleep 1;
    my $out = slurp('tfiles/stdout');
    is $out, "100\n";

    $service->stop;
    is $service->status->status, 'not running', 'stopped successfully';

    my $invalid_service = Ubic::Service::SimpleDaemon->new({
        name => 'limited_service',
        bin => ['perl', '-e', 'sleep 100'],
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ulimit => {
            BLAH => 100,
        },
    });
    my $exception = exception { $invalid_service->start };
    like $exception, qr/Failed to create daemon: '.*Error: setrlimit: Unknown limit 'BLAH'/s, 'start with invalid ulimit fails';
}

__PACKAGE__->new->runtests;
