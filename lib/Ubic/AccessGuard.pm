package Ubic::AccessGuard;

use strict;
use warnings;

# ABSTRACT: guard for operations with temporarily different effective uid

=head1 SYNOPSIS

    use Ubic::AccessGuard;

    # change effective uid and effective gid to $credentials
    $guard = Ubic::AccessGuard->new($credentials);

    # change them back
    undef $guard;

=head1 DESCRIPTION

Ubic::AccessGuard temporarily changes effective uid and gid, and restore it back on destruction.

It's usage is limited, because when effective uid is not equal to real uid, perl automatically turns on tainted mode.
Because of this, only tainted-safe code should be called when AccessGuard is active.
Ubic doesn't start services under this guard, but uses it when acquiring locks and writing service status files.

=head1 INTERFACE SUPPORT

This is considered to be a non-public class. Its interface is subject to change without notice.

=head1 METHODS

=over

=cut

use Params::Validate;
use Ubic::Result qw(result);
use Ubic::Credentials;
use Carp;
use Scalar::Util qw(weaken);
use Try::Tiny;

# AccessGuard is actually a singleton - there can't be two different guards, since process can't have two euids.
# So we keep weakref to any created AccessGuard.
my $ag_ref;

=item C<< new($credentials) >>

Construct new access guard object.

User and group will be changed into given C<$credentials>. It will be changed back on guard's desctruction.

=cut

sub new {
    my $class = shift;
    my ($credentials) = validate_pos(@_, { isa => 'Ubic::Credentials' });

    if ($ag_ref) {
        # oops, another AccessGuard already exists
        my $ag = $$ag_ref;
        if ($ag->{credentials}->eq($credentials)) {
            # new guard is the same as old guard
            return $ag;
        }
        else {
            croak "Can't create AccessGuard for ".$credentials->as_string.", there is already another AccessGuard for ".$ag->{credentials}->as_string;
        }
    }

    my $self = bless {
        credentials => $credentials,
    } => $class;

    try {
        $credentials->set_effective;
    }
    catch {
        die result('unknown', "$_");
    };

    $ag_ref = \$self;
    weaken($ag_ref);

    return $self;
}

sub DESTROY {
    my $self = shift;
    local $@;

    $self->{credentials}->reset_effective;
}

=back

=cut

1;
