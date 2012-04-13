#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 29;
use Test::Exception;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};

use t::Utils;
use IO::Handle;
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
        bin => [$perl, 't/bin/locking-daemon'],
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
    ok(!check_daemon("tfiles/pid", { quiet => 1 }), 'ubic-guardian is dead');

    start_daemon({
        bin => [$perl, 't/bin/locking-daemon'],
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
                STDOUT->flush;
                exit;
            };
            sleep 100;
        },
        name => 'abc',
        stdout => 'tfiles/kill_default.log',
        pidfile => 'tfiles/pid',
        ubic_log => 'tfiles/ubic.term.log',
    });
    sleep 1;
    stop_daemon('tfiles/pid');
    unless( is(slurp('tfiles/kill_default.log'), "sigterm caught\n", 'default kill signal is SIGTERM - log written') ) {
        # something is wrong
        # this diag can look ugly, but it's the easiest way to figure out what's wrong with some cpantesters
        diag(slurp('tfiles/ubic.term.log'));
    }


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
    sleep 1;
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
        term_timeout => 2,
    });
    sleep 1;
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
        term_timeout => 2,
    });
    sleep 1;
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
        sleep 1;
    };

    $start->();
    is(stop_daemon('tfiles/pid'), 'stopped', 'stop with large enough timeout is ok');

    $start->();
    throws_ok(sub {
        stop_daemon('tfiles/pid', { timeout => 1 });
    }, qr/failed to stop daemon/, 'stop with small timeout fails');

    is(stop_daemon('tfiles/pid', { timeout => 5 }), 'stopped', 'start and stop with large enough timeout is ok');

    throws_ok(sub {
        stop_daemon('tfiles/pid', { timeout => 'abc' });
    }, qr/did not pass regex check/, 'stop with invalid timeout fails parameters validation');
}

# stop_daemon params validation (2)
{
    lives_ok(sub { stop_daemon('aeuklryaweur') }, 'stop_daemon with non-existing pidfile is ok');
    dies_ok(sub { stop_daemon({ pidfile => 'auerawera' }) }, 'calling stop_daemon with invalid parameters is wrong');
}

# ubic_log (5)
{
    {
        rebuild_tfiles; local_ubic;
        start_daemon({
            bin => "sleep 10",
            pidfile => "tfiles/pid",
            ubic_log => 'tfiles/ubic.log',
        });
        stop_daemon('tfiles/pid');
        my $log = slurp('tfiles/ubic.log');
        like($log, qr/daemon \d+ exited by sigterm$/m, 'exit via sigterm');
    }

    {
        rebuild_tfiles; local_ubic;
        start_daemon({
            bin => ['perl', '-le', '$SIG{TERM} = sub { print "term"; exit }; sleep 10'],
            pidfile => "tfiles/pid",
            stdout => 'tfiles/log',
            stderr => 'tfiles/err.log',
            ubic_log => 'tfiles/ubic.log',
        });
        sleep 1;
        stop_daemon('tfiles/pid');
        my $log = slurp('tfiles/ubic.log');
        like($log, qr/daemon \d+ exited$/m, 'exit voluntarily');
    }

    {
        rebuild_tfiles; local_ubic;
        start_daemon({
            bin => ['perl', '-e', 'sleep 1; exit 3'],
            pidfile => "tfiles/pid",
            ubic_log => 'tfiles/ubic.log',
        });
        sleep 2;
        my $log = slurp('tfiles/ubic.log');
        like($log, qr/daemon \d+ failed, exit code 3$/m, 'exit with non-zero code');
    }

    {
        rebuild_tfiles; local_ubic;
        # there are two options:
        # 1) daemon exits before ubic-guardian finishes its initialization; in this case, start_daemon will throw an exception
        # 2) ubic-guardian finishes its initialization and then daemon exits; in this case, we check for ubic.log
        eval {
            start_daemon({
                bin => ['perl', '-e', 'exit 3'],
                pidfile => "tfiles/pid",
                ubic_log => 'tfiles/ubic.log',
            });
        };
        if ($@) {
            like($@, qr/daemon exited immediately/, 'daemon exits immediately, before guardian initialization');
        }
        else {
            sleep 1;
            my $log = slurp('tfiles/ubic.log');
            like($log, qr/daemon \d+ failed, exit code 3$/m, 'daemon exits immediately, after guardian initialization');
        }
    }

    {
        rebuild_tfiles; local_ubic;
        start_daemon({
            bin => ['perl', '-e', '$SIG{TERM} = "IGNORE"; sleep 30'],
            pidfile => "tfiles/pid",
            ubic_log => 'tfiles/ubic.log',
            term_timeout => 1,
        });
        sleep 1;
        stop_daemon('tfiles/pid');
        my $log = slurp('tfiles/ubic.log');
        like($log, qr/daemon \d+ probably killed by SIGKILL$/m, 'exit via sigkill');
    }

    {
        rebuild_tfiles; local_ubic;
        start_daemon({
            bin => ['perl', '-e', '$SIG{TERM} = "IGNORE"; sleep 30'],
            pidfile => "tfiles/pid",
            ubic_log => 'tfiles/ubic.log',
            term_timeout => 1,
        });
        sleep 1;
        my $status = check_daemon('tfiles/pid');
        kill 9 => $status->pid;
        sleep 1;
        stop_daemon('tfiles/pid');
        my $log = slurp('tfiles/ubic.log');
        like($log, qr/daemon \d+ failed with signal KILL \(9\)$/m, 'exit via signal to daemon');
    }
}
