#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More tests => 5;

use Config;
my $perl = $Config{perlpath};

use t::Utils;
use IO::Handle;

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);
use Ubic::Credentials;

rebuild_tfiles();
xsystem('chmod -R 777 tfiles');

start_daemon({
    bin => 'sleep 10',
    pidfile => 'tfiles/pid',
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
    ubic_log => 'tfiles/ubic.log',
    credentials => Ubic::Credentials->new(user => 'daemon'),
});
ok(check_daemon('tfiles/pid'), 'daemon is running');

sub file2uid {
    my @stat = stat(shift);
    return $stat[4];
}
is(file2uid('tfiles/pid'), scalar(getpwnam('root')), 'pidfile belongs to root');
is(file2uid('tfiles/stdout'), scalar(getpwnam('daemon')), 'stdout belongs to daemon');
is(file2uid('tfiles/stderr'), scalar(getpwnam('daemon')), 'stderr belongs to daemon');
is(file2uid('tfiles/ubic.log'), scalar(getpwnam('root')), 'stderr belongs to root');

stop_daemon('tfiles/pid');
