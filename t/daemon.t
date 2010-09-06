#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 23;
use Test::Exception;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};

use t::Utils;
rebuild_tfiles();

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
        stdout => 'tfiles/non-existent/forbidden.log',
        pidfile => 'tfiles/pid',
    })
},
qr{\QError: Can't write to 'tfiles/non-existent/forbidden.log'\E},
'start_daemon reports correct errrors');

# reviving after kill -9 on ubic-guardian (4)
{
    start_daemon({
        bin => "$perl t/bin/locking-daemon",
        pidfile => 'tfiles/pid',
        stdout => 'tfiles/stdout',
        stderr => 'tfiles/stderr',
        ubic_log => 'tfiles/ubic.log',
    });
    ok(check_daemon("tfiles/pid"), 'daemon started');

    chomp(my $piddata = slurp('tfiles/pid/pid'));
    my ($pid) = $piddata =~ /pid\s+(\d+)/ or die "Unknown pidfile content '$piddata'";
    kill -9 => $pid;
    sleep 1;
    {
        my $ignore_warn = ignore_warn(qr{(killing unguarded daemon|pidfile tfiles/pid removed)});
        ok(!check_daemon("tfiles/pid"), 'ubic-guardian is dead');
    }

    start_daemon({
        bin => "$perl t/bin/locking-daemon",
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

# term_timeout (5)
{
    start_daemon({
        function => sub {
            $SIG{TERM} = sub {
                print "sigterm caught\n";
                exit;
            };
            sleep 100;
        },
        name => 'abc',
        stdout => 'tfiles/kill_default.log',
        pidfile => 'tfiles/pid',
        ubic_log => 'tfiles/ubic.term.log',
    });
    stop_daemon('tfiles/pid');
    is(slurp('tfiles/kill_default.log'), "sigterm caught\n", 'default kill signal is SIGTERM - log written');

    start_daemon({
        function => sub {
            $SIG{TERM} = sub {
                print "sigterm caught\n";
                exit;
            };
            sleep 100;
        },
        name => 'abc',
        stdout => 'tfiles/kill_zero_timeout.log',
        pidfile => 'tfiles/pid',
        ubic_log => 'tfiles/ubic.term.log',
        term_timeout => 0,
    });
    stop_daemon('tfiles/pid');
    is(slurp('tfiles/kill_zero_timeout.log'), "", 'when term_timeout is 0, SIGKILL is sent immediately');

    start_daemon({
        function => sub {
            $SIG{TERM} = sub {
                $|++;
                print "sigterm caught\n";
                exit;
            };
            sleep 100;
        },
        name => 'abc',
        stdout => 'tfiles/kill_term.log',
        pidfile => 'tfiles/pid',
        ubic_log => 'tfiles/ubic.term.log',
        term_timeout => 1,
    });
    stop_daemon('tfiles/pid');
    is(slurp('tfiles/kill_term.log'), "sigterm caught\n", 'process caught SIGTERM and written something in log');

    start_daemon({
        function => sub {
            $SIG{TERM} = sub {
                sleep 4;
                print "sigterm caught\n";
                exit;
            };
            sleep 100;
        },
        name => 'abc',
        stdout => 'tfiles/kill_4.log',
        pidfile => 'tfiles/pid',
        ubic_log => 'tfiles/ubic.term.log',
        term_timeout => 1,
    });
    stop_daemon('tfiles/pid');
    is(slurp('tfiles/kill_4.log'), '', 'process caught SIGTERM but was too slow to do anything about it');

    throws_ok(sub {
        start_daemon({
            function => sub {
                $SIG{TERM} = sub {
                    print "sigterm caught\n";
                    exit;
                };
                sleep 100;
            },
            name => 'abc',
            stdout => 'tfiles/kill_segv.log',
            pidfile => 'tfiles/pid',
            ubic_log => 'tfiles/ubic.term.log',
            term_timeout => 'abc',
        })
    }, qr/did not pass regex check/, 'term_timeout values are limited to integers');
}

# stop_daemon options (4)
{
    my $start = sub {
        start_daemon({
            function => sub {
                $SIG{TERM} = 'IGNORE'; # ubic-guardian will send sigterm, and we want it to fail
                sleep 100;
            },
            name => 'abc',
            pidfile => 'tfiles/pid',
            ubic_log => 'tfiles/ubic.term.log',
            term_timeout => 3,
        });
    };

    $start->();
    is(stop_daemon('tfiles/pid'), 'stopped', 'stop with large enough timeout is ok');

    $start->();
    throws_ok(sub {
        stop_daemon('tfiles/pid', { timeout => 2 });
    }, qr/failed to stop daemon/, 'stop with small timeout fails');

    is(stop_daemon('tfiles/pid', { timeout => 4 }), 'stopped', 'start and stop with large enough timeout is ok');

    throws_ok(sub {
        stop_daemon('tfiles/pid', { timeout => 'abc' });
    }, qr/did not pass regex check/, 'stop with invalid timeout fails parameters validation');
}

# stop_daemon params validation (2)
{
    lives_ok(sub { stop_daemon('aeuklryaweur') }, 'stop_daemon with non-existing pidfile is ok');
    dies_ok(sub { stop_daemon({ pidfile => 'auerawera' }) }, 'calling stop_daemon with invalid parameters is wrong');
}
