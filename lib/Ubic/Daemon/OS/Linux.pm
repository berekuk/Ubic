package Ubic::Daemon::OS::Linux;

use strict;
use warnings;

# ABSTRACT: linux-specific daemonize helpers

=head1 DESCRIPTION

These functions use C<< /proc >> virtual filesystem for some operations.

There is another C<< Ubic::Daemon::OS::POSIX >> module, which is more generic and should work on all POSIX-compatible systems.
But this module is older and supposedly more stable. (Also, sometimes it's more optimal, compare implementation of C<close_all_fh()>, for example).

=cut

use POSIX;

use parent qw(Ubic::Daemon::OS);

sub pid2guid {
    my ($self, $pid) = @_;

    unless ($self->pid_exists($pid)) {
        return; # process not found
    }
    my $opened = open(my $fh, '<', "/proc/$pid/stat");
    unless ($opened) {
        # open failed
        my $error = $!;
        unless ($self->pid_exists($pid)) {
            return; # process exited right now
        }
        die "Open /proc/$pid/stat failed: $!";
    }
    my $line = <$fh>;
    # cut first two fields (pid and process name)
    # since process name can contain spaces, we can't just split line by \s+
    $line =~ s/^\d+\s+\([^)]*\)\s+//;

    my @fields = split /\s+/, $line;
    my $guid = $fields[19];
    return $guid;
}

sub pid2cmd {
    my ($self, $pid) = @_;

    my $daemon_cmd_fh;
    unless (open $daemon_cmd_fh, '<', "/proc/$pid/cmdline") {
        # this can happen if pid got reused and now it belongs to the kernel process, e.g., [kthreadd]
        warn "Can't open daemon's cmdline: $!";
        return 'unknown';
    }
    my $daemon_cmd = <$daemon_cmd_fh>;
    unless ($daemon_cmd) {
        # strange, open succeeded but file is empty
        # this can happen, though, for example if pid belongs to the kernel thread
        warn "Can't read daemon cmdline";
        return 'unknown';
    }
    $daemon_cmd =~ s/\x{00}$//;
    $daemon_cmd =~ s/\x{00}/ /g;
    close $daemon_cmd_fh;

    return $daemon_cmd;
}

sub close_all_fh {
    my ($self, @except) = @_;

    my @fd_nums = map { s!^.*/!!; $_ } glob("/proc/$$/fd/*");
    for my $fd (@fd_nums) {
        next if grep { $_ == $fd } @except;
        POSIX::close($fd);
    }
}

sub pid_exists {
    my ($self, $pid) = @_;
    my $check_interval = 0.001;

    # Wait at most 127ms before giving up and returning false.
    # This helps to avoid race: check can return false negative
    # for its own process immediately after 'fork' in some cases.
    for (my $i = 0; 1; $i++) {
        if (-d "/proc/$pid" && -e "/proc/$pid/exe") {
            return 1;
        }

        last if $i >= 7;

        warn "Failed to check PID '$pid' in '/proc', attempt $i. Sleeping '$check_interval' before next check."
        sleep $check_interval;
        $check_interval = $check_interval*2;
    }

    return;
}

1;
