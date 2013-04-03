package Ubic::Daemon;

use strict;
use warnings;

# ABSTRACT: daemon management utilities

=head1 SYNOPSIS

    use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

    start_daemon({bin => '/bin/sleep', pidfile => "/var/lib/something/pid"});
    stop_daemon("/var/lib/something/pid");

    $daemon_status = check_daemon("/var/lib/something/pid");

=head1 DESCRIPTION

This module provides functions which let you daemonize any binary or perl coderef.

Main source of knowledge if daemon is still running is pidfile, which is locked all the time after daemon was created.

Note that pidfile format is unreliable and can change in future releases (it's actually even not a file, it's a dir with several files inside it),
so if you need to get daemon's pid, don't try to read pidfile directly, use C<check_daemon()> function.

=over

=cut

use IO::Handle;
use IO::Select;
use POSIX qw(setsid :sys_wait_h);
use Time::HiRes qw(sleep);
use Params::Validate qw(:all);
use Carp;
use Config;

use Ubic::Lockf;
use Ubic::AccessGuard;
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

{
    my @signame;
    sub _signame {
        my $signum = shift;
        unless (@signame) {
            @signame = split /\s+/, $Config{sig_name};
        }
        return $signame[$signum];

    }
}

sub _log {
    my $fh = shift;
    return unless defined $fh;
    print {$fh} '[', scalar(localtime), "]\t$$\t", @_, "\n";
}

sub _log_exit_code {
    my ($fh, $code, $pid) = @_;
    if ($code == 0) {
        _log($fh, "daemon $pid exited");
        return;
    }

    my $msg = "daemon $pid failed with \$? = $?";
    if (my $signal = $? & 127) {
        my $signame = _signame($signal);
        if (defined $signame) {
            $msg = "daemon $pid failed with signal $signame ($signal)";
        }
        else {
            $msg = "daemon $pid failed with signal $signal";
        }
    }
    elsif ($? & 128) {
        $msg = "daemon $pid failed, core dumped";
    }
    elsif (my $code = $? >> 8) {
        $msg = "daemon $pid failed, exit code $code";
    }
    _log($fh, $msg);
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

Optional filename of ubic log. Log will contain some technical information about running daemon.

If not specified, this logging facility will be disabled.

=item I<cwd>

Change working directory before starting a daemon. Optional.

=item I<env>

Modify environment before starting a daemon. Optional. Must be a plain hashref if specified.

=item I<proxy_logs>

Boolean flag.

If enabled, C<ubic-guardian> will replace daemon's stdout and stderr filehandles with pipes, proxy all data to the log files, and reopen them on I<SIGHUP>.

There're two reasons why this is not the default:

1) It's a bit slower than allowing the daemon to write its logs itself;

2) The code is new and more complex than the simple "spawn the daemon and wait for it to finish".

On the other hand, using this feature allows you to reopen all logs without restarting the service.

=item I<credentials>

Set given credentials before execing into a daemon. Optional, must be an C<Ubic::Credentials> object.

=item I<start_hook>

Optional callback that will be executed before execing into a daemon.

This option is a generalization of I<cwd> and I<env> options. One useful application of it is setting ulimits: they won't affect your main process, since this hook will be executed in the context of double-forked process.

Note that hook is called *before* the credentials are set. Raising the ulimits won't work otherwise.

=item I<term_timeout>

Number of seconds to wait between sending I<SIGTERM> and I<SIGKILL> to the daemon on stopping.

Zero value means that guardian will send I<SIGKILL> to the daemon immediately.

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
        term_timeout => { type => SCALAR, default => 10, regex => qr/^\d+$/ },
        cwd => { type => SCALAR, optional => 1 },
        env => { type => HASHREF, optional => 1 },
        proxy_logs => { type => SCALAR, optional => 1 },
        credentials => { isa => 'Ubic::Credentials', optional => 1 },
        start_hook => { type => CODEREF, optional => 1 },
    });
    my           ($bin, $function, $name, $pidfile, $stdout, $stderr, $ubic_log, $term_timeout, $cwd, $env, $credentials, $start_hook, $proxy_logs)
    = @options{qw/ bin   function   name   pidfile   stdout   stderr   ubic_log   term_timeout   cwd   env   credentials   start_hook   proxy_logs /};
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

    pipe my ($read_pipe, $write_pipe) or die "pipe failed";
    my $child;

    unless ($child = fork) {
        die "fork failed" unless defined $child;

        my $ubic_fh;
        my $lock;
        my $instant_exit = sub {
            close($ubic_fh) if $ubic_fh;
            STDOUT->flush;
            STDERR->flush;
            undef $lock;
            POSIX::_exit(0); # don't allow any cleanup to happen - this process was forked from unknown environment, don't want to run unknown destructors
        };

        eval {
            close($read_pipe) or die "Can't close read pipe: $!";
            # forking child - will reopen standard streams, daemonize itself, fork into daemon binary and wait for it

            {
                my $tmp_pid = fork() and POSIX::_exit(0); # detach from parent process
                die "fork failed" unless defined $tmp_pid;
            }

            # Close all inherited filehandles except $write_pipe (it will be closed explicitly).
            # Do not close fh if uses 'function' option instead of 'bin'
            # ('function' support should be removed altogether because of this, actually; it's evil).
            if ($bin) {
                my $write_pipe_fd_num = fileno($write_pipe);
                $OS->close_all_fh($write_pipe_fd_num); # except pipe
            }

            my $open_handles_sub = sub {
                my $guard;
                $guard = Ubic::AccessGuard->new($credentials) if $credentials;
                open STDOUT, ">>", $stdout or die "Can't write to '$stdout': $!";
                open STDERR, ">>", $stderr or die "Can't write to '$stderr': $!";
                if (defined $ubic_log) {
                    open $ubic_fh, ">>", $ubic_log or die "Can't write to '$ubic_log': $!";
                    $ubic_fh->autoflush(1);
                }
            };
            $open_handles_sub->();
            my $stdin = '/dev/null';
            open STDIN, "<", $stdin or die "Can't read from '$stdin': $!";

            $SIG{HUP} = 'ignore';
            $0 = "ubic-guardian $name";
            setsid; # ubic-daemon gets it's own session
            _log($ubic_fh, "guardian name: $0");

            _log($ubic_fh, "obtaining lock...");

            # We're passing 'timeout' option to lockf call to get rid of races.
            # There should be no races when Ubic::Daemon is used in context of
            # ubic service, because services have an additional lock, but
            # Ubic::Daemon can be useful without services as well.
            $lock = $pid_state->lock(5) or die "Can't lock $pid_state";

            $pid_state->remove;
            _log($ubic_fh, "got lock");

            my %daemon_pipes;
            if (defined $proxy_logs) {
                for my $handle (qw/stdout stderr/) {
                    pipe my ($read, $write) or die "pipe for daemon $handle failed";
                    $daemon_pipes{$handle} = {read => $read, write => $write};
                }
            }
            my $child;
            if ($child = fork) {
                # guardian

                _log($ubic_fh, "guardian pid: $$");
                _log($ubic_fh, "daemon pid: $child");

                my $child_guid = $OS->pid2guid($child);
                unless ($child_guid) {
                    if ($OS->pid_exists($child)) {
                        die "Can't detect guid";
                    }
                    $? = 0;
                    unless (waitpid($child, WNOHANG) == $child) {
                        die "No pid $child but waitpid didn't collect $child status";
                    }
                    _log_exit_code($ubic_fh, $?, $child);
                    $pid_state->remove();
                    die "daemon exited immediately";
                }
                _log($ubic_fh, "child guid: $child_guid");
                $pid_state->write({ pid => $child, guid => $child_guid });

                my $kill_sub = sub {
                    if ($term_timeout) {
                        _log($ubic_fh, "SIGTERM timeouted after $term_timeout second(s)");
                    }
                    _log($ubic_fh, "sending SIGKILL to $child");
                    kill -9 => $child;
                    _log($ubic_fh, "daemon $child probably killed by SIGKILL");
                    $pid_state->remove();
                    $instant_exit->();
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
                undef $write_pipe;

                if (defined $proxy_logs) {
                    $SIG{HUP} = sub {
                        eval { $open_handles_sub->() };
                        if ($@) {
                            _log($ubic_fh, "failed to reopen stdout/stderr handles: $@");
                            $kill_sub->();
                        }
                        else {
                            _log($ubic_fh, "reopened stdout/stderr");
                        }
                    };

                    for my $handle (qw/stdout stderr/) {
                        close($daemon_pipes{$handle}{write}) or do {
                            _log($ubic_fh, "Can't close $handle write: $!");
                            die "Can't close $handle write: $!" 
                        };
                    }
                    my $sel = IO::Select->new();
                    $sel->add($daemon_pipes{stdout}{read}, $daemon_pipes{stderr}{read});
                    my $BUFF_SIZE = 4096;
                    READ:
                    while ($OS->pid_exists($child)) { # this loop is needed because of timeout in can_read
                        while (my @ready = $sel->can_read(1)) {
                            my $exhausted = 0;
                            for my $handle (@ready) {
                                my $data;
                                my $bytes_read = sysread($handle, $data, $BUFF_SIZE);
                                die "Can't poll $handle: $!" unless defined $bytes_read; # handle EWOULDBLOCK?
                                $exhausted += 1 if $bytes_read == 0;
                                if (fileno $handle == fileno $daemon_pipes{stdout}{read}) {
                                    print STDOUT $data;
                                }
                                if (fileno $handle == fileno $daemon_pipes{stderr}{read}) {
                                    print STDERR $data;
                                }
                            }
                            last READ if $exhausted == @ready;
                        }
                    }
                }

                $? = 0;
                waitpid($child, 0);
                my $code = $?;
                if ($sigterm_sent and ($code & 127) == &POSIX::SIGTERM) {
                    # it's ok, we probably sent this signal ourselves
                    _log($ubic_fh, "daemon $child exited by sigterm");
                }
                else {
                    _log_exit_code($ubic_fh, $code, $child);
                }
                $pid_state->remove;
            }
            else {
                # daemon

                die "fork failed" unless defined $child;

                # start new process group - become immune to kills at parent group and at the same time be able to kill all processes below
                setpgrp;
                $0 = "ubic-daemon $name";

                if (defined $cwd) {
                    chdir $cwd or die "chdir to '$cwd' failed: $!";
                }
                if (defined $env) {
                    for my $key (keys %{ $env }) {
                        $ENV{$key} = $env->{$key};
                    }
                }
                $start_hook->() if $start_hook;
                $credentials->set() if $credentials;

                close($ubic_fh) if defined $ubic_fh;
                $lock->dissolve;

                print {$write_pipe} "execing into daemon\n" or die "Can't write to pipe: $!";
                close($write_pipe) or die "Can't close pipe: $!";
                undef $write_pipe;

                if (defined $proxy_logs) {
                    # redirecting standard streams to pipes
                    close($daemon_pipes{$_}{read}) or die "Can't close $_ read: $!" for qw/stdout stderr/;
                    open STDOUT, '>&=', $daemon_pipes{stdout}{write} or die "Can't open stdout write: $!";
                    open STDERR, '>&=', $daemon_pipes{stderr}{write} or die "Can't open stderr write: $!";
                }

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
        $instant_exit->();
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
    my $pidfile = shift;
    my $options = validate(@_, {
        quiet => { optional => 1 },
    });

    my $print = sub {
        print @_, "\n" unless $options->{quiet};
    };

    my $pid_state = Ubic::Daemon::PidState->new($pidfile);
    return undef if $pid_state->is_empty;

    my $lock = $pid_state->lock;
    my $piddata = $pid_state->read;
    unless ($lock) {
        # locked => daemon is alive
        return Ubic::Daemon::Status->new({ pid => $piddata->{daemon}, guardian_pid => $piddata->{pid} });
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
        $print->("pidfile $pidfile removed - daemon with cached pid $piddata->{daemon} not found");
        return undef;
    }

    # TODO - wrap in eval and return undef if pid2cmd fails?
    my $daemon_cmd = $OS->pid2cmd($piddata->{daemon});

    my $guid = $OS->pid2guid($piddata->{daemon});
    unless ($guid) {
        $print->("daemon '$daemon_cmd' from $pidfile just disappeared");
        return undef;
    }
    if ($guid eq $piddata->{guid}) {
        $print->("killing unguarded daemon '$daemon_cmd' with pid $piddata->{daemon} from $pidfile");
        kill -9 => $piddata->{daemon};
        $pid_state->remove;
        $print->("pidfile $pidfile removed");
        return undef;
    }
    $print->("daemon pid $piddata->{daemon} cached in pidfile $pidfile, ubic-guardian not found");
    $print->("current process '$daemon_cmd' with pid $piddata->{daemon} has wrong guid ($piddata->{guid}, expected $guid) and will not be killed");
    $print->("removing pidfile $pidfile");
    $pid_state->remove;
    return undef;
}

=back

=head1 BUGS AND CAVEATS

Probably. But it definitely is ready for production usage.

This module is not compatible with Windows by now. It can be fixed by implementing correct C<Ubic::Daemon::OS::Windows> module.

If you wonder why there are C<ubic-guardian> processes in your C<ps> output, see L<Ubic::Manual::FAQ>, answer is there.

=head1 SEE ALSO

L<Ubic::Service::SimpleDaemon> - simplest ubic service which uses Ubic::Daemon

There are also a plenty of other daemonizers on CPAN:

L<MooseX::Daemonize>, L<Proc::Daemon>, L<Daemon::Generic>, L<Net::Server::Daemonize>.

=cut

1;
