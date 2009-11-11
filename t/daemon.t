#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 17;
use Test::Exception;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

start_daemon({
    bin => "sleep 10",
    pidfile => "tfiles/pid",
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
    ubic_log => 'tfiles/ubic.log',
});
ok(check_daemon("tfiles/pid"), 'daemon is running');
dies_ok(sub {
    start_daemon({
        bin => "sleep 10",
        pidfile => "tfiles/pid",
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
}, 'start_daemon fails if daemon is already started');

#diag("stop here\n");
#exit;

stop_daemon('tfiles/pid');
ok(!(check_daemon("tfiles/pid")), 'daemon is not running');

start_daemon({
    bin => "sleep 2",
    pidfile => "tfiles/pid",
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
    ubic_log => 'tfiles/ubic.log',
});
ok(check_daemon("tfiles/pid"), 'daemon is running again');
sleep 4;
ok(!(check_daemon("tfiles/pid")), 'daemon stopped after several seconds');

start_daemon({
    function => sub { sleep 2 },
    name => 'callback-daemon',
    pidfile => "tfiles/pid",
    stdout => 'tfiles/stdout',
    stderr => 'tfiles/stderr',
    ubic_log => 'tfiles/ubic.log',
});
ok(check_daemon("tfiles/pid"), 'daemon in callback mode started');
sleep 4;
ok(!(check_daemon("tfiles/pid")), 'callback daemon stopped after several seconds');

throws_ok(sub {
    start_daemon({
        function => sub { sleep 2 },
        name => 'abc',
        stdout => '/forbidden.log',
        pidfile => 'tfiles/pid',
    })
},
qr{\QError: Can't write to '/forbidden.log'\E},
'start_daemon reports correct errrors');

# reviving after kill -9 on ubic-guardian (4)
{
    start_daemon({
        bin => 'lockf -t 0 -k tfiles/locking-daemon sleep 100',
        pidfile => 'tfiles/pid',
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
    ok(check_daemon("tfiles/pid"), 'daemon started');

    chomp(my $piddata = xqx('cat tfiles/pid'));
    my ($pid) = $piddata =~ /pid\s+(\d+)/ or die "Unknown pidfile content '$piddata'";
    kill -9 => $pid;
    sleep 1;
    ok(!check_daemon("tfiles/pid"), 'ubic-guardian is dead');

    start_daemon({
        bin => 'lockf -t 0 -k tfiles/locking-daemon sleep 100',
        pidfile => 'tfiles/pid',
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
    sleep 1;
    ok(check_daemon("tfiles/pid"), 'daemon started again');
    stop_daemon('tfiles/pid');
    ok(!check_daemon("tfiles/pid"), 'daemon stopped');
}

# old format compatibility (5)
{
    start_daemon({
        bin => 'lockf -t 0 -k tfiles/locking-daemon sleep 100',
        pidfile => 'tfiles/pid',
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
    ok(check_daemon("tfiles/pid"), 'daemon with pidfile in new format started');

    chomp(my $piddata = xqx('cat tfiles/pid'));
    my ($pid) = $piddata =~ /pid\s+(\d+)/ or die "Unknown pidfile content '$piddata'";
    xqx("echo $pid >tfiles/pid"); # replacing pidfile with content in old format (pid only)
    ok(check_daemon("tfiles/pid"), 'daemon with pidfile in old format is still alive');

    stop_daemon('tfiles/pid');
    ok(!check_daemon("tfiles/pid"), 'daemon with pidfile in old format stopped');

    start_daemon({
        bin => 'lockf -t 0 -k tfiles/locking-daemon sleep 100',
        pidfile => 'tfiles/pid',
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
    ok(check_daemon("tfiles/pid"), 'daemon started after being stopped with pidfile in new format');
    stop_daemon('tfiles/pid');
    ok(!check_daemon("tfiles/pid"), 'last stop completed successfully');
}
