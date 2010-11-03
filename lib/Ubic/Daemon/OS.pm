package Ubic::Daemon::OS;

use strict;
use warnings;

# ABSTRACT: base class for os-specific daemon methods

=head1 METHODS

=over

=item B<new>

Trivial constructor.

=cut
sub new {
    return bless {} => shift;
}

=item B<pid2guid($pid)>

Get pid's guid. Guid is some kind of additional process identifier on systems where we can think of one.

On Linux, for example, it's the timestamp in jiffies when process started.

Returns undef if pid not found, throws exception on other errors.

=cut
sub pid2guid {
    die 'not implemented';
}

=item B<pid2cmd($pid)>

Get process cmd line from pid.

=cut
sub pid2cmd {
    die 'not implemented';
}

=item B<close_all_fh(@except)>

Close all file descriptors except ones specified as arguments.

=cut
sub close_all_fh {
    die 'not implemented';
}

=item B<pid_exists($pid)>

Check if process with given pid exists.

=cut
sub pid_exists {
    die 'not implemented';
}

=back

=cut

1;
