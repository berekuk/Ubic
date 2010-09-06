package Ubic::Daemon::Status;

use strict;
use warnings;

# ABSTRACT: daemon status structure

=head1 SYNOPSIS

    say $status->pid;

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

=back

=head1 SEE ALSO

L<Ubic::Daemon> - general process daemonizator

=cut

1;
