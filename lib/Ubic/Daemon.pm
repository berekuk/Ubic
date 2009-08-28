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

This module tries to safely start and daemonize any binary or any perl function.

Main source of knowledge if daemon is still running is pidfile, which is locked all the time after daemon was created.

=over

=cut

use IO::Handle;
use POSIX qw(setsid);
use Yandex::X;
use Yandex::Lockf;

use Carp;

use Exporter;
use base qw(Exporter);
our @EXPORT_OK = qw(start_daemon stop_daemon check_daemon);
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

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

Start daemon. Params:

=over

=item I<bin>

Binary which will be daemonized.

=item I<function>

Function which will be daemonized. One and only one of I<function> and I<bin> must be specified.

=item I<name>

Name of guardian process. Guardian will be named "ubic-guardian $name".

If not specified, I<bin>'s value will be assumed, or C<anonymous> when daemonizing perl code.

=item I<pidfile>

Pidfile. It will be locked for all time when service will be running. It will contain pid of daemon.

=item I<stdout>

Write all daemon's output to given file. If not specified, all output will be redirected to C</dev/null>.

=item I<stderr>

Write all daemon's error output to given file. If not specified, all stderr will be redirected to C</dev/null>.

=item I<ubic_log>

Filename of ubic log. It will contain some technical information about running daemon.

If not specified, C</dev/null> will be assumed.

=back

=cut
sub start_daemon($) {
    my %options = validate(@_, {
        bin => { type => SCALAR, optional => 1 },
        function => { type => CODEREF, optional => 1 },
        name => { type => SCALAR, optional => 1 },
        pidfile => { type => SCALAR },
        stdout => { type => SCALAR, default => '/dev/null' },
        stderr => { type => SCALAR, default => '/dev/null' },
        ubic_log => { type => SCALAR, default => '/dev/null' },
        user => { type => SCALAR, optional => 1 },
    });
    my           ($bin, $function, $name, $pidfile, $stdout, $stderr, $ubic_log, $user)
    = @options{qw/ bin   function   name   pidfile   stdout   stderr   ubic_log   user /};
    if (not defined $bin and not defined $function) {
        croak "One of 'bin' and 'function' should be specified";
    }
    if (defined $bin and defined $function) {
        croak "Only one of 'bin' and 'function' should be specified";
    }
    unless (defined $name) {
        $name = $bin || 'anonymous';
    }

    my $stdin = '/dev/null';

    pipe my ($read_pipe, $write_pipe) or die "pipe failed";
    my $child;

    unless ($child = xfork) {
        my $ubic_fh;
        my $lock;
        my $instant_exit = sub {
            my $status = shift;
            close($ubic_fh) if $ubic_fh;
            STDOUT->flush;
            STDERR->flush;
            undef $lock;
            POSIX::_exit($status); # don't allow to lock to be released - this process was forked from unknown environment, don't want to run unknown destructors
        };

        eval {
            xclose($read_pipe);
            # forking child - will reopen standard streams, daemonize itself, fork into daemon binary and wait for it

            xfork() and POSIX::_exit(0); # detach from parent process

            open STDOUT, ">>", $stdout or die "Can't write to '$stdout'";
            open STDERR, ">>", $stderr or die "Can't write to '$stderr'";
            open STDIN, "<", $stdin or die "Can't read from '$stdin'";
            $ubic_fh = xopen(">>", $ubic_log);
            $ubic_fh->autoflush(1);
            $SIG{HUP} = 'ignore';
            $0 = "ubic-guardian $name";
            setsid; # ubic-daemon gets it's own session
            xprint($ubic_fh, "self name: $0\n");

            xprint($ubic_fh, "[$$] getting lock...\n");
            $lock = lockf($pidfile, {nonblocking => 1});
            xprint($ubic_fh, "[$$] got lock\n");
            my $pid_fh = xopen(">", $pidfile);
            xprint($pid_fh, $$);
            $pid_fh->flush;

            if (defined $user) {
                my $id = getpwnam($user);
                unless (defined $id) {
                    die "User '$user' not found";
                }
                POSIX::setuid($id);
            }

            if (my $child = xfork) {
                # guardian

                xprint($ubic_fh, "guardian pid: $$\n");
                xprint($ubic_fh, "daemon pid: $child\n");

                $SIG{TERM} = sub {
                    xprint($ubic_fh, "sending SIGKILL to $child\n");
                    kill -9 => $child; # TODO - should be "soft kill", "wait some time", "hard kill"
                    xprint($ubic_fh, "child probably killed\n");
                    $instant_exit->(0);
                };
                xclose($write_pipe);

                waitpid($child, 0);
                if ($? > 0) {
                    warn "Daemon failed: $?";
                    xprint($ubic_fh, "daemon failed: $?");
                    $instant_exit->(1);
                }
                xprint($ubic_fh, "daemon exited");
                $instant_exit->(0);
            }
            else {
                # daemon

                # start new process group - became immune to kills at parent group and at the same time be able to kill all processes below
                setpgrp;
                $0 = "ubic-daemon $name";

                xprint($write_pipe, "xexecing into daemon\n");
                xclose($write_pipe);

                if ($bin) {
                    xexec($bin); # finally, run underlying binary
                }
                else {
                    $function->();
                }

            }
        };
        if ($write_pipe) {
            print {$write_pipe} "Error: $@\n";
        }
        $instant_exit->(1);
    }
    waitpid($child, 0); # child should've exited immediately
    xclose($write_pipe);

    my $out = '';
    while ( my $data = <$read_pipe>) {
        $out .= $data;
    }
    xclose($read_pipe);
    if ($out =~ /xexecing into daemon/) {
        # TODO - check daemon's name to make sure that xexec happened
        return;
    }
    die "Failed to create daemon: '$out'";
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

