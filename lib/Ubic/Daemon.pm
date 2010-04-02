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

Pidfile format is unreliable and can change in future releases.
If you really need to get daemon's pid, save it from daemon or ask me for public pidfile-reading API in this module.

=over

=cut

use IO::Handle;
use POSIX qw(setsid);
use Yandex::X;
use Yandex::Lockf 3.0;

use Carp;

use Exporter;
use base qw(Exporter);
our @EXPORT_OK = qw(start_daemon stop_daemon check_daemon);
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

use Params::Validate qw(:all);

# get pid's guid
# returns undef if pid not found, throws exception on other errors
sub _pid2guid($) {
    my $pid = shift;
    unless (-d "/proc/$pid") {
        return; # process not found
    }
    my $opened = open(my $fh, '<', "/proc/$pid/stat");
    unless ($opened) {
        # open failed
        my $error = $!;
        unless (-d "/proc/$pid") {
            return; # process exited right now
        }
        die "Open /proc/$pid/stat failed: $!";
    }
    my $line = <$fh>;
    my @fields = split /\s+/, $line;
    my $guid = $fields[21];
    return $guid;
}

# clean pidfile, actually
# this method should be called only when pidfile is locked (check before removing?)
sub _remove_pidfile($) {
    my ($file) = validate_pos(@_, { type => SCALAR });
    xopen('>', $file); # we can't unlink pidfile - Yandex::Lockf can cause race conditions in that case
}

# write guardian pid and guid to pidfile
sub _write_pidfile($$) {
    my $file = shift;
    my $params = validate(@_, {
        pid => 1,
        guid => 1,
    });
    my ($pid, $guid) = @$params{qw/ pid guid /};
    my $self_pid = $$;
    my $fh = xopen('>', $file);
    print {$fh} "pid $self_pid\n";
    print {$fh} "guid $guid\n";
    print {$fh} "daemon $pid\n";
    $fh->flush;
    xclose($fh);
}

sub _read_pidfile($) {
    my ($file) = validate_pos(@_, { type => SCALAR });
    my $fh = xopen('<', $file);
    my $content = join '', <$fh>;
    if ($content =~ /\A (\d+) \Z/x) {
        # old format
        return { pid => $1, format => 'old' };
    }
    elsif ($content =~ /\A pid \s+ (\d+) \n guid \s+ (\d+) (?: \n daemon \s+ (\d+) )? \Z/x) {
        # new format
        return { pid => $1, guid => $2, daemon => $3, format => 'new' };
    }
    elsif ($content =~ /\A pid \s+ (\d+) \n started \s+ (\d+) (?: \n daemon \s+ (\d+) )? \Z/x) {
        # really deprecated format from testing 0.9.5 version
        return { pid => $1, format => 'old' };
    }
    else {
        # broken pidfile
        return;
    }
}

sub _log {
    my $fh = shift;
    return unless defined $fh;
    xprint($fh, '[', scalar(localtime), "]\t$$\t", @_, "\n");
}

=item B<stop_daemon($pidfile)>

=item B<stop_daemon($pidfile, $options)>

Stop daemon which was started with C<$pidfile>.

It sends I<SIGTERM> to process with pid specified in C<$pidfile> until it will stop to exist (according to C<check_daemon()> method). If it fails to stop process after several seconds, exception will be raised.

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
        timeout => { default => 5, regex => qr/^\d+$/ },
    });
    my $timeout = $options->{timeout};

    unless (-s $pidfile) {
        return 'not running';
    }

    my $piddata = _read_pidfile($pidfile);
    unless ($piddata) {
        die "Can't read $pidfile"; # or silently remove?
    }
    my $pid = $piddata->{pid};

    unless (check_daemon($pidfile)) {
        return 'not running';
    }
    kill 15 => $pid;
    for my $trial (1..$timeout) {
        unless (check_daemon($pidfile)) {
            return 'stopped';
        }
        sleep(1);
    }
    unless (check_daemon($pidfile)) {
        return 'stopped';
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

Pidfile. It will be locked for a whole time of service's work. It will contain pid of daemon.

=item I<stdout>

Write all daemon's output to given file. If not specified, all output will be redirected to C</dev/null>.

=item I<stderr>

Write all daemon's error output to given file. If not specified, all stderr will be redirected to C</dev/null>.

=item I<ubic_log>

Filename of ubic log. It will contain some technical information about running daemon.

If not specified, C</dev/null> will be assumed.

=item I<term_timeout>

Can contain integer number of seconds to wait between sending I<SIGTERM> and I<SIGKILL> to daemon.

Default is zero, which means sigkill daemon immediately.

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
        term_timeout => { type => SCALAR, default => 0, regex => qr/^\d+$/ },
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
        $name = $bin || 'anonymous';
    }

    if (check_daemon($pidfile)) {
        croak "Daemon with pidfile $pidfile already running, can't start";
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

            # Close all inherited filehandles except $write_pipe (it will be closed explicitly).
            # Do not close fh if uses 'function' option instead of 'bin' ('function' should be deprecated).
            if ($bin) {
                my @fd_nums = map { s!^.*/!!; $_ } glob("/proc/$$/fd/*");
                my $write_pipe_fd_num = fileno($write_pipe);
                foreach (@fd_nums) {
                    POSIX::close($_) if ($_ != $write_pipe_fd_num);
                }
            }

            open STDOUT, ">>", $stdout or die "Can't write to '$stdout'";
            open STDERR, ">>", $stderr or die "Can't write to '$stderr'";
            open STDIN, "<", $stdin or die "Can't read from '$stdin'";
            $ubic_fh = xopen(">>", $ubic_log);
            $ubic_fh->autoflush(1);
            $SIG{HUP} = 'ignore';
            $0 = "ubic-guardian $name";
            setsid; # ubic-daemon gets it's own session
            _log($ubic_fh, "self name: $0");

            _log($ubic_fh, "[$$] getting lock...");
            $lock = lockf($pidfile, { nonblocking => 1 }) or die "Can't lock $pidfile";
            _remove_pidfile($pidfile);
            _log($ubic_fh, "[$$] got lock");

            if (defined $user) {
                my $id = getpwnam($user);
                unless (defined $id) {
                    die "User '$user' not found";
                }
                POSIX::setuid($id);
            }

            if (my $child = xfork) {
                # guardian

                my $child_guid = _pid2guid($child);
                _write_pidfile($pidfile, { pid => $child, guid => $child_guid });

                _log($ubic_fh, "guardian pid: $$");
                _log($ubic_fh, "daemon pid: $child");

                my $kill_sub = sub {
                    if ($term_timeout) {
                        _log($ubic_fh, "SIGTERM timeouted after $term_timeout second(s)");
                    }
                    _log($ubic_fh, "sending SIGKILL to $child");
                    kill -9 => $child;
                    _log($ubic_fh, "child probably killed by SIGKILL");
                    _remove_pidfile($pidfile);
                    $instant_exit->(0);
                };

                $SIG{TERM} = sub {
                    if ($term_timeout > 0) {
                        $SIG{ALRM} = $kill_sub;
                        alarm($term_timeout);
                        _log($ubic_fh, "sending SIGTERM to $child");
                        kill -15 => $child;
                    }
                    else {
                        $kill_sub->();
                    }
                };
                xprint($write_pipe, "pidfile written\n");
                xclose($write_pipe);

                waitpid($child, 0);
                if ($? > 0) {
                    my $msg;
                    if ($? & 127) {
                        $msg = "Daemon failed with signal ".($? & 127);
                    }
                    else {
                        $msg = "Daemon failed: $?";
                    }
                    warn $msg;
                    _log($ubic_fh, $msg);
                    _remove_pidfile($pidfile);
                    $instant_exit->(1);
                }
                _log($ubic_fh, "daemon exited");
                _remove_pidfile($pidfile);
                $instant_exit->(0);
            }
            else {
                # daemon

                # start new process group - become immune to kills at parent group and at the same time be able to kill all processes below
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
            $write_pipe->flush;
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
    if ($out =~ /^xexecing into daemon$/m and $out =~ /^pidfile written$/m) {
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
    unless (-s $pidfile) {
        return 0;
    }
    my $lock = lockf($pidfile, { nonblocking => 1 });
    unless ($lock) {
        # locked => daemon is alive
        return 1;
    }

    # acquired lock when pidfile exists
    # checking whether just ubic-guardian died or whole process group
    my $piddata = _read_pidfile($pidfile);
    if ($piddata->{format} eq 'old') {
        # ok, old-style pidfile, can't check daemon, let's just pretend that everything is ok
        _read_pidfile($pidfile);
        return 0;
    }
    unless ($piddata->{daemon}) {
        die "pidfile $pidfile exists, but daemon pid is not saved in it, so existing unguarded daemon can't be killed";
    }
    unless (-d "/proc/$piddata->{daemon}") {
        _remove_pidfile($pidfile);
        print "pidfile $pidfile removed - daemon with cached pid $piddata->{daemon} not found\n";
        return 0;
    }
    my $daemon_cmd_fh = xopen('<', "/proc/$piddata->{daemon}/cmdline");
    my $daemon_cmd = <$daemon_cmd_fh>;
    $daemon_cmd =~ s/\x{00}$//;
    $daemon_cmd =~ s/\x{00}/ /g;
    xclose($daemon_cmd_fh);

    my @procdir_stat = stat("/proc/$piddata->{daemon}");
    my $guid = _pid2guid($piddata->{daemon});
    unless ($guid) {
        print "daemon '$daemon_cmd' from $pidfile just disappeared\n";
        return 0;
    }
    if ($guid eq $piddata->{guid}) {
        warn "killing unguarded daemon '$daemon_cmd' with pid $piddata->{daemon} from $pidfile\n";
        kill -9 => $piddata->{daemon};
        _remove_pidfile($pidfile);
        print "pidfile $pidfile removed\n";
        return 0;
    }
    print "daemon pid $piddata->{daemon} cached in pidfile $pidfile, ubic-guardian not found\n";
    print "current process '$daemon_cmd' with that pid looks too fresh and will not be killed\n";
    print "pidfile $pidfile removed\n";
    _remove_pidfile($pidfile);
    return 0;
}

=back

=head1 BUGS

Probably lots of them.

=head1 SEE ALSO

L<Ubic::Service::SimpleDaemon>

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

