package Ubic::Daemon;

use strict;
use warnings;

=head1 NAME

Ubic::Daemon - toolkit for creating daemonized process

=head1 SYNOPSIS

    use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);
    start_daemon({bin => '/bin/sleep', pidfile => "/var/lib/something/pid"});
    stop_daemon("/var/lib/something/pid");
    check_daemon("/var/lib/something/pid");

=head1 DESCRIPTION

This module tries to safely start and daemonize any binary.

Main source of knowledge if daemon is still running is pidfile, which is locked all the time after daemon was created.

=over

=cut

use IO::Handle;
use Yandex::X;
use Yandex::Lockf;

use Exporter;
use base qw(Exporter);
our @EXPORT_OK = qw(start_daemon stop_daemon check_daemon);

use Params::Validate qw(:all);

=item B<stop_daemon($pidfile)>

Stop daemon which was started with $pidfile.

=cut
sub stop_daemon($) {
    my ($pidfile) = validate_pos(@_, 1);

    my $fh = xopen('<', $pidfile);
    chomp(my $pid = <$fh>);

    my $killed;
    for my $trial (1..5) {
        unless (check_daemon($pidfile)) {
            if ($killed) {
                return 'stopped';
            }
            else {
                return 'not running';
            }
        }
        if ($killed) {
            sleep(1);
        }
        kill 15 => $pid;
        $killed++;
    }
    die "failed to stop daemon with pidfile '$pidfile' (pid $pid)";
}

=item B<start_daemon($params)>

Start daemon. See source for params (sorry).

=cut
sub start_daemon($) {
    my %options = validate(@_, {
        bin => { type => SCALAR },
        pidfile => { type => SCALAR },
        stdout => { type => SCALAR, default => '/dev/null' },
        stderr => { type => SCALAR, default => '/dev/null' },
        ubic_log => { type => SCALAR, default => '/dev/null' },
    });
    my           ($bin, $pidfile, $stdout, $stderr, $ubic_log)
    = @options{qw/ bin   pidfile   stdout   stderr   ubic_log /};

    my $stdin = '/dev/null';

    if (my $child = xfork) {
        # main process
        waitpid($child, 0); # child should fork again and return
        if ($? > 0) {
            die "Failed to create daemon: $?";
        }
    } else {
        # forking child - will reopen standard streams, fork and return
        open STDOUT, ">>", $stdout or die "Can't write to '$stdout'";
        open STDERR, ">>", $stderr or die "Can't write to '$stderr'";
        open STDIN, "<", $stdin or die "Can't read from '$stdin'";
        my $ubic_fh = xopen(">>", $ubic_log);
        $ubic_fh->autoflush(1);
        $SIG{HUP} = 'ignore';
        $0 = "ubic-daemon $bin";
        xprint($ubic_fh, "self name: $0\n");

        # check that lock is free now
        # this is a possible race condition, i know...
        my $lock = lockf($pidfile, {nonblocking => 1});
        undef $lock;

        if (xfork) {
            exit; # let caller continue, last moment to check that most commands succeeded
            # TODO - we could implement some protocol to ask running daemonizer if everything is ok... socket or something?
        } else {
            if (my $child = xfork) {
                # daemonizer
                my $lock = lockf($pidfile, {nonblocking => 1});
                my $pid_fh = xopen(">", $pidfile);
                xprint($pid_fh, $$);
                $pid_fh->flush;
                xprint($ubic_fh, "daemonizer pid: $$\n");
                xprint($ubic_fh, "daemon pid: $child\n");

                $SIG{TERM} = sub {
                    xprint($ubic_fh, "sending SIGKILL to $child\n");
                    kill -9 => $child; # TODO - should be "soft kill", "wait some time", "hard kill"
                    xprint($ubic_fh, "child probably killed\n");
                    exit; # SIGTERM is a correct way to stop daemon
                };
                waitpid($child, 0);
                if ($? > 0) {
                    die "Daemon failed: $?";
                }
                exit;
            } else {
                # start new process group - became immune to kills at parent group and at the same time be able to kill all processes below
                ### TODO - should we start process group twice - for daemonizer and for daemon?
                ### daemonizer needs new group to be immune to various console signals
                ### daemon needs group, because daemonizer want to "kill -9" it when desperate
                setpgrp;

                xexec($bin); # finally, run underlying binary
            }
        }
    }
}

=item B<check_daemon($pidfile)>

Check whether daemon is running.

Returns true if it is so.

=cut
sub check_daemon {
    my ($pidfile) = @_;
    eval {
        lockf($pidfile, {nonblocking => 1});
    };
    unless ($@) {
        return;
    }
    if ($@ =~ /temporarily unavailable/) {
        return 1;
    }
    else {
        die "Failed to take lock: $@";
    }
}

=back

=head1 BUGS

See the code for many critical TODO sections.

=head1 SEE ALSO

L<Ubic::Service::SimpleDaemon>

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

