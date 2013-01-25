package Ubic::Daemon::Status;

use strict;
use warnings;

# ABSTRACT: daemon status structure

=head1 SYNOPSIS

    say $status->pid;
    say $status->guardian_pid;

=cut

use Params::Validate;

=head1 METHODS

=over

=item B<< new($options) >>

Constructor. Should be called from L<Ubic::Daemon> only.

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        pid => 1,
        guardian_pid => 1,
    });
    return bless $params => $class;
}

=item B<< pid() >>

Get daemon's PID.

=cut
sub pid {
    my $self = shift;
    validate_pos(@_);
    return $self->{pid};
}

=item B<< guardian_pid() >>

Get guardian's PID.

=cut
sub guardian_pid {
    my $self = shift;
    validate_pos(@_);
    return $self->{guardian_pid};
}

=back

=head1 SEE ALSO

L<Ubic::Daemon> - general process daemonizator

=cut

1;
