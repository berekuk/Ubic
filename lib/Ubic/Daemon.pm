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
use Ubic::Lockf;
use Time::HiRes qw(sleep);

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

# this method should be called only when pidfile is locked (check before removing?)
sub _remove_pidfile($) {
    my ($file) = validate_pos(@_, { type => SCALAR });
    if (-d $file) {
        if (-e "$file/pid") {
            unlink "$file/pid" or die "Can't remove $file/pid: $!";
        }
    }
    else {
        unlink $file or die "Can't remove $file: $!";
    }
}

sub _lock_pidfile($;$) {
    my ($pidfile, $timeout) = validate_pos(@_, { type => SCALAR }, 0);
    $timeout ||= 0;
    if (-d $pidfile) {
        # new-style pidfile
        return lockf("$pidfile/lock", { timeout => $timeout });
    }
    else {
        return lockf($pidfile, { blocking => 0 });
    }
}

# write guardian pid and guid to pidfile
sub _write_pidfile($$) {
    my $file = shift;
    unless (-d $file) {
        die "piddir $file not exists";
    }
    my $params = validate(@_, {
        pid => 1,
        guid => 1,
    });
    my ($pid, $guid) = @$params{qw/ pid guid /};
    my $self_pid = $$;
    open my $fh, '>', "$file/pid.new" or die "Can't write '$file/pid.new': $!";
    print {$fh} "pid $self_pid\n";
    print {$fh} "guid $guid\n";
    print {$fh} "daemon $pid\n";
    $fh->flush;
    close $fh or die "Can't close '$file/pid.new': $!";
    rename "$file/pid.new" => "$file/pid" or die "Can't commit pidfile $file: $!";
}

# read daemon info from pidfile
# returns undef if pidfile not found
# throws exceptions when content is invalid
sub _read_pidfile($) {
    my ($file) = validate_pos(@_, { type => SCALAR });
    my $content;
    my $parse_content = sub {
        if ($content =~ /\A pid \s+ (\d+) \n guid \s+ (\d+) (?: \n daemon \s+ (\d+) )? \Z/x) {
            # new format
            return { pid => $1, guid => $2, daemon => $3, format => 'new' };
        }
        else {
            die "invalid pidfile content in pidfile $file";
        }
    };
    if (-d $file) {
        # pidfile as dir
        my $open_success = open my $fh, '<', "$file/pid";
        unless ($open_success) {
            if ($!{ENOENT}) {
                return; # pidfile not found, daemon is not running
            }
            else {
                die "Failed to open '$file/pid': $!";
            }
        }
        $content = join '', <$fh>;
        return $parse_content->();
    }
    else {
        # deprecated - single pidfile without piddir
        if (-f $file and not -s $file) {
            return; # empty pidfile - old way to stop services
        }
        open my $fh, '<', $file or die "Failed to open $file: $!";
        $content = join '', <$fh>;
        if ($content =~ /\A (\d+) \Z/x) {
            # old format
            return { pid => $1, format => 'old' };
        }
        else {
            return $parse_content->();
        }
    }
}

sub _log {
    my $fh = shift;
    return unless defined $fh;
    print {$fh} '[', scalar(localtime), "]\t$$\t", @_, "\n";
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
        timeout => { default => 30, regex => qr/^\d+$/ },
    });
    my $timeout = $options->{timeout} if defined $options->{timeout};

    if (not -d $pidfile and not -s $pidfile) {
        return 'not running';
    }
    my $piddata = _read_pidfile($pidfile);
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

Start daemon. Params:

=over

=item I<bin>

Binary which will be daemonized.

Can be string or arrayref with arguments. Arrayref-style values are recommended in complex cases, because otherwise C<exec()> can invoke sh shell which will immediately exit on sigterm.

=item I<function>

Function which will be daemonized. One and only one of I<function> and I<bin> must be specified.

Function daemonization is a dangerous feature and will probably be deprecated and removed in future.

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
        ubic_log => { type => SCALAR, default => '/dev/null' },
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
    if (-e $pidfile and not -d $pidfile) {
        print "converting $pidfile to dir\n";
        unlink $pidfile or die "Can't unlink $pidfile: $!";
    }
    unless (-d $pidfile) {
        mkdir $pidfile or die "Can't create $pidfile: $!";
    }

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
            my $status = shift;
            close($ubic_fh) if $ubic_fh;
            STDOUT->flush;
            STDERR->flush;
            undef $lock;
            POSIX::_exit($status); # don't allow to lock to be released - this process was forked from unknown environment, don't want to run unknown destructors
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
            # Do not close fh if uses 'function' option instead of 'bin' ('function' should be deprecated).
            if ($bin) {
                my @fd_nums = map { s!^.*/!!; $_ } glob("/proc/$$/fd/*");
                my $write_pipe_fd_num = fileno($write_pipe);
                foreach (@fd_nums) {
                    POSIX::close($_) if ($_ != $write_pipe_fd_num);
                }
            }

            open STDOUT, ">>", $stdout or die "Can't write to '$stdout': $!";
            open STDERR, ">>", $stderr or die "Can't write to '$stderr': $!";
            open STDIN, "<", $stdin or die "Can't read from '$stdin': $!";
            open $ubic_fh, ">>", $ubic_log or die "Can't write to '$ubic_log': $!";
            $ubic_fh->autoflush(1);
            $SIG{HUP} = 'ignore';
            $0 = "ubic-guardian $name";
            setsid; # ubic-daemon gets it's own session
            _log($ubic_fh, "self name: $0");

            _log($ubic_fh, "[$$] getting lock...");

            # We're passing 'timeout' option to lockf call to get rid of races.
            # There should be no races when Ubic::Daemon is used in context of
            # ubic service, because services has additional lock, but
            # Ubic::Daemon can be useful without services as well.
            $lock = _lock_pidfile($pidfile, 5) or die "Can't lock $pidfile";

            _remove_pidfile($pidfile);
            _log($ubic_fh, "[$$] got lock");

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
                print {$write_pipe} "pidfile written\n" or die "Can't write to pipe: $!";
                close $write_pipe or die "Can't close pipe: $!";

                $? = 0;
                waitpid($child, 0);
                if ($? > 0) {
                    my $msg;
                    if ($? & 127) {
                        $msg = "Daemon $child failed with signal ".($? & 127);
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

Returns true if it is so.

=cut
sub check_daemon {
    my ($pidfile) = @_;
    if (not -d $pidfile and not -s $pidfile) {
        return 0; # empty, old-style pidfile
    }
    if (-d $pidfile and not -e "$pidfile/pid") {
        return 0;
    }

    my $lock = _lock_pidfile($pidfile);
    unless ($lock) {
        # locked => daemon is alive
        return 1;
    }

    my $piddata = _read_pidfile($pidfile);
    unless ($piddata) {
        return 0;
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
    unless (-d "/proc/$piddata->{daemon}") {
        _remove_pidfile($pidfile);
        print "pidfile $pidfile removed - daemon with cached pid $piddata->{daemon} not found\n";
        return 0;
    }
    open my $daemon_cmd_fh, '<', "/proc/$piddata->{daemon}/cmdline" or die "Can't open daemon's cmdline: $!";
    my $daemon_cmd = <$daemon_cmd_fh>;
    $daemon_cmd =~ s/\x{00}$//;
    $daemon_cmd =~ s/\x{00}/ /g;
    close $daemon_cmd_fh;

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

