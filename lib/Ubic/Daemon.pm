package Ubic::Daemon;

use strict;
use warnings;

# ABSTRACT: toolkit for creating daemonized process

=head1 SYNOPSIS

    use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

    start_daemon({bin => '/bin/sleep', pidfile => "/var/lib/something/pid"});
    stop_daemon("/var/lib/something/pid");

    $daemon_status = check_daemon("/var/lib/something/pid");

=head1 DESCRIPTION

This module can safely start and daemonize any binary or any perl coderef.

Main source of knowledge if daemon is still running is pidfile, which is locked all the time after daemon was created.

Pidfile format is unreliable and can change in future releases (it's actually even not a file, it's a dir with several files inside it),
so if you need to get daemon's pid, use check_daemon() result.

=over

=cut

use IO::Handle;
use POSIX qw(setsid);
use Time::HiRes qw(sleep);
use Params::Validate qw(:all);
use Carp;

use Ubic::Lockf;
use Ubic::Daemon::Status;
use Ubic::Daemon::PidState;

use parent qw(Exporter);
our @EXPORT_OK = qw(start_daemon stop_daemon check_daemon);
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

our $OS;
sub import {
    my %module = (
        linux   => 'Linux',
    );

    # UBIC_DAEMON_OS support is here only for tests
    my $module = $ENV{UBIC_DAEMON_OS} || $module{$^O} || 'POSIX';

    require "Ubic/Daemon/OS/$module.pm";
    $OS = eval "Ubic::Daemon::OS::$module->new";
    unless ($OS) {
        die "failed to initialize OS-specific module $module: $@";
    }
    __PACKAGE__->export_to_level(1, @_);
}

sub _log {
    my $fh = shift;
    return unless defined $fh;
    print {$fh} '[', scalar(localtime), "]\t$$\t", @_, "\n";
}

=item B<stop_daemon($pidfile)>

=item B<stop_daemon($pidfile, $options)>

Stop daemon which was started with C<$pidfile>.

It sends I<SIGTERM> to process with pid specified in C<$pidfile> until it will stop to exist (according to C<check_daemon()> method).

If it fails to stop process after several seconds, exception will be raised (this should never happen, assuming you have enough grants).

Options:

=over

=item I<timeout>

Number of seconds to wait before raising exception that daemon can't be stopped.

=back

Return value: C<not running> if daemon is already not running; C<stopped> if daemon is stopped by I<SIGTERM>.

=cut
sub stop_daemon($;@) {
    my ($pidfile, @tail) = validate_pos(@_, { type => SCALAR }, 0);
    my $options = validate(@tail, {
        timeout => { default => 30, regex => qr/^\d+$/ },
    });
    my $timeout = $options->{timeout} if defined $options->{timeout};

    # TODO - move this check into Ubic::Daemon::PidState
    my $pid_state = Ubic::Daemon::PidState->new($pidfile);
    return 'not running' if $pid_state->is_empty;

    my $piddata = $pid_state->read;
    unless ($piddata) {
        return 'not running';
    }
    my $pid = $piddata->{pid};

    unless (check_daemon($pidfile)) {
        return 'not running';
    }
    kill 15 => $pid;
    my $trial = 1;
    {
        my $sleep = 0.1;
        my $total_sleep = 0;
        while (1) {
            unless (check_daemon($pidfile)) {
                return 'stopped';
            }
            last if $total_sleep >= $timeout;
            sleep($sleep);
            $total_sleep += $sleep;
            $sleep += 0.1 * $trial if $sleep < 1;
            $trial++;
        }
    }
    unless (check_daemon($pidfile)) {
        return 'stopped';
    }
    die "failed to stop daemon with pidfile '$pidfile' (pid $pid, timeout $timeout, trials $trial)";
}

=item B<start_daemon($params)>

Start daemon.

Throws exception if anything fails.

Successful completion doesn't mean much, though, since daemon can fail any moment later, and we have no idea when its initialization stage finishes.

Parameters:

=over

=item I<bin>

Binary which will be daemonized.

Can be string or arrayref with arguments. Arrayref-style values are recommended in complex cases, because otherwise C<exec()> can invoke sh shell which will immediately exit on sigterm.

=item I<function>

Function which will be daemonized. One and only one of I<function> and I<bin> must be specified.

Function daemonization is a dangerous feature and will probably be deprecated and removed in future.

=item I<name>

Name of guardian process. Guardian will be named "ubic-guardian $name".

If not specified, I<bin>'s value will be used, or C<anonymous> when daemonizing perl code.

=item I<pidfile>

Pidfile is a dir in local filesystem which will be used as a storage of daemon's info.

It will be created if necessary, assuming that its parent dir exists.

=item I<stdout>

Write all daemon's output to given file. If not specified, all output will be redirected to C</dev/null>.

=item I<stderr>

Write all daemon's error output to given file. If not specified, all stderr will be redirected to C</dev/null>.

=item I<ubic_log>

Optional filename of ubic log. It will contain some technical information about running daemon.

If not specified, this logging facility will be disabled.

=item I<term_timeout>

Can contain integer number of seconds to wait between sending I<SIGTERM> and I<SIGKILL> to daemon.

Zero value means that guardian will send sigkill to daemon immediately.

Default is 10 seconds.

=back

=cut
sub start_daemon($) {
    my %options = validate(@_, {
        bin => { type => SCALAR | ARRAYREF, optional => 1 },
        function => { type => CODEREF, optional => 1 },
        name => { type => SCALAR, optional => 1 },
        pidfile => { type => SCALAR },
        stdout => { type => SCALAR, default => '/dev/null' },
        stderr => { type => SCALAR, default => '/dev/null' },
        ubic_log => { type => SCALAR, optional => 1 },
        user => { type => SCALAR, optional => 1 },
        term_timeout => { type => SCALAR, default => 10, regex => qr/^\d+$/ },
    });
    my           ($bin, $function, $name, $pidfile, $stdout, $stderr, $ubic_log, $user, $term_timeout)
    = @options{qw/ bin   function   name   pidfile   stdout   stderr   ubic_log   user term_timeout /};
    if (not defined $bin and not defined $function) {
        croak "One of 'bin' and 'function' should be specified";
    }
    if (defined $bin and defined $function) {
        croak "Only one of 'bin' and 'function' should be specified";
    }
    unless (defined $name) {
        if (ref $bin) {
            $name = join ' ', @$bin;
        }
        else {
            $name = $bin || 'anonymous';
        }
    }

    if (check_daemon($pidfile)) {
        croak "Daemon with pidfile $pidfile already running, can't start";
    }

    my $pid_state = Ubic::Daemon::PidState->new($pidfile);
    $pid_state->init;

    my $stdin = '/dev/null';

    pipe my ($read_pipe, $write_pipe) or die "pipe failed";
    my $child;

    unless ($child = fork) {
        unless (defined $child) {
            die "fork failed";
        }
        my $ubic_fh;
        my $lock;
        my $instant_exit = sub {
            my $status = shift; # nobody cares for this status, anyway...
            close($ubic_fh) if $ubic_fh;
            STDOUT->flush;
            STDERR->flush;
            undef $lock;
            POSIX::_exit($status); # don't allow any cleanup to happen - this process was forked from unknown environment, don't want to run unknown destructors
        };

        eval {
            close($read_pipe) or die "Can't close read pipe: $!";
            # forking child - will reopen standard streams, daemonize itself, fork into daemon binary and wait for it

            {
                my $tmp_pid = fork() and POSIX::_exit(0); # detach from parent process
                unless (defined $tmp_pid) {
                    die "fork failed";
                }
            }

            # Close all inherited filehandles except $write_pipe (it will be closed explicitly).
            # Do not close fh if uses 'function' option instead of 'bin'
            # ('function' support should be removed altogether because of this, actually; it's evil).
            if ($bin) {
                my $write_pipe_fd_num = fileno($write_pipe);
                $OS->close_all_fh($write_pipe_fd_num); # except pipe
            }

            open STDOUT, ">>", $stdout or die "Can't write to '$stdout': $!";
            open STDERR, ">>", $stderr or die "Can't write to '$stderr': $!";
            open STDIN, "<", $stdin or die "Can't read from '$stdin': $!";
            if (defined $ubic_log) {
                open $ubic_fh, ">>", $ubic_log or die "Can't write to '$ubic_log': $!";
                $ubic_fh->autoflush(1);
            }
            $SIG{HUP} = 'ignore';
            $0 = "ubic-guardian $name";
            setsid; # ubic-daemon gets it's own session
            _log($ubic_fh, "guardian name: $0");

            _log($ubic_fh, "getting lock...");

            # We're passing 'timeout' option to lockf call to get rid of races.
            # There should be no races when Ubic::Daemon is used in context of
            # ubic service, because services has additional lock, but
            # Ubic::Daemon can be useful without services as well.
            $lock = $pid_state->lock(5) or die "Can't lock $pid_state";

            $pid_state->remove;
            _log($ubic_fh, "got lock");

            if (defined $user) {
                my $id = getpwnam($user);
                unless (defined $id) {
                    die "User '$user' not found";
                }
                POSIX::setuid($id);
            }

            my $child;
            if ($child = fork) {
                # guardian

                my $child_guid = $OS->pid2guid($child);
                $pid_state->write({ pid => $child, guid => $child_guid });

                _log($ubic_fh, "guardian pid: $$");
                _log($ubic_fh, "daemon pid: $child");

                my $kill_sub = sub {
                    if ($term_timeout) {
                        _log($ubic_fh, "SIGTERM timeouted after $term_timeout second(s)");
                    }
                    _log($ubic_fh, "sending SIGKILL to $child");
                    kill -9 => $child;
                    _log($ubic_fh, "child probably killed by SIGKILL");
                    $pid_state->remove();
                    $instant_exit->(0);
                };

                my $sigterm_sent;
                $SIG{TERM} = sub {
                    if ($term_timeout > 0) {
                        $SIG{ALRM} = $kill_sub;
                        alarm($term_timeout);
                        _log($ubic_fh, "sending SIGTERM to $child");
                        kill -15 => $child;
                        $sigterm_sent = 1;
                    }
                    else {
                        $kill_sub->();
                    }
                };
                print {$write_pipe} "pidfile written\n" or die "Can't write to pipe: $!";
                close $write_pipe or die "Can't close pipe: $!";

                $? = 0;
                waitpid($child, 0);
                if ($? > 0) {
                    my $msg;
                    my $signal = $? & 127;
                    if ($signal) {
                        if ($sigterm_sent && $signal == &POSIX::SIGTERM) {
                            # it's ok, we probably sent this signal ourselves
                            _log($ubic_fh, "daemon exited by sigterm");
                            $pid_state->remove;
                            $instant_exit->(0);
                        }
                        $msg = "Daemon $child failed with signal $signal";
                    }
                    else {
                        $msg = "Daemon failed: $?";
                    }
                    _log($ubic_fh, $msg);
                    $pid_state->remove;
                    $instant_exit->(1);
                }
                _log($ubic_fh, "daemon exited");
                $pid_state->remove;
                $instant_exit->(0);
            }
            else {
                # daemon
                unless (defined $child) {
                    die "fork failed";
                }

                # start new process group - become immune to kills at parent group and at the same time be able to kill all processes below
                setpgrp;
                $0 = "ubic-daemon $name";

                print {$write_pipe} "execing into daemon\n" or die "Can't write to pipe: $!";
                close($write_pipe) or die "Can't close pipe: $!";

                # finally, run underlying binary
                if (ref $bin) {
                    exec(@$bin) or die "exec failed: $!";
                }
                elsif ($bin) {
                    exec($bin) or die "exec failed: $!";
                }
                else {
                    $function->();
                }

            }
        };
        if ($write_pipe) {
            print {$write_pipe} "Error: $@\n";
            $write_pipe->flush;
        }
        $instant_exit->(1);
    }
    waitpid($child, 0); # child should've exited immediately
    close($write_pipe) or die "Can't close write_pipe: $!";

    my $out = '';
    while ( my $data = <$read_pipe>) {
        $out .= $data;
    }
    close($read_pipe) or die "Can't close read_pipe: $!";
    if ($out =~ /^execing into daemon$/m and $out =~ /^pidfile written$/m) {
        # TODO - check daemon's name to make sure that exec happened
        return;
    }
    die "Failed to create daemon: '$out'";
}

=item B<check_daemon($pidfile)>

Check whether daemon is running.

Returns instance of L<Ubic::Daemon::Status> class if daemon is alive, and false otherwise.

=cut
sub check_daemon {
    my ($pidfile) = @_;

    my $pid_state = Ubic::Daemon::PidState->new($pidfile);
    return undef if $pid_state->is_empty;

    my $lock = $pid_state->lock;
    my $piddata = $pid_state->read;
    unless ($lock) {
        # locked => daemon is alive
        return Ubic::Daemon::Status->new({ pid => $piddata->{daemon} });
    }

    unless ($piddata) {
        return undef;
    }

    # acquired lock when pidfile exists
    # checking whether just ubic-guardian died or whole process group
    if ($piddata->{format} and $piddata->{format} eq 'old') {
        die "deprecated pidfile format detected\n";
    }
    unless ($piddata->{daemon}) {
        use Data::Dumper;
        die "pidfile $pidfile exists, but daemon pid is not saved in it, so existing unguarded daemon can't be killed (piddata: ".Dumper($piddata).")";
    }
    unless ($OS->pid_exists($piddata->{daemon})) {
        $pid_state->remove;
        print "pidfile $pidfile removed - daemon with cached pid $piddata->{daemon} not found\n";
        return undef;
    }

    my $daemon_cmd = $OS->pid2cmd($piddata->{daemon});

    my $guid = $OS->pid2guid($piddata->{daemon});
    unless ($guid) {
        print "daemon '$daemon_cmd' from $pidfile just disappeared\n";
        return undef;
    }
    if ($guid eq $piddata->{guid}) {
        warn "killing unguarded daemon '$daemon_cmd' with pid $piddata->{daemon} from $pidfile\n";
        kill -9 => $piddata->{daemon};
        $pid_state->remove;
        print "pidfile $pidfile removed\n";
        return undef;
    }
    print "daemon pid $piddata->{daemon} cached in pidfile $pidfile, ubic-guardian not found\n";
    print "current process '$daemon_cmd' with that pid looks too fresh and will not be killed\n";
    print "pidfile $pidfile removed\n";
    $pid_state->remove;
    return undef;
}

=back

=head1 BUGS AND CAVEATS

Probably. But it definitely is ready for production usage.

This module currently is Linux-specific, because it uses C</proc> some magic. Patches are very welcome to fix this.

If you can't figure out why there are C<ubic-guardian> processes in your C<ps> output, see L<Ubic::Manual::FAQ>, answer is there.

=head1 SEE ALSO

L<Ubic::Service::SimpleDaemon> - simplest ubic service which uses Ubic::Daemon

There are also a plenty of other daemonizers on CPAN:

L<MooseX::Daemonize>, L<Proc::Daemon>, L<Daemon::Generic>, L<Net::ServeR::Daemonize>.

=cut

1;
