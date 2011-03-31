package Ubic::AccessGuard;

use strict;
use warnings;

# ABSTRACT: class which guards simple service operations

=head1 SYNOPSIS

    use Ubic::AccessGuard;

    $guard = Ubic::AccessGuard->new($service); # change effective uid and effective gid to $service->user and $service->group
    undef $guard; # change them back

=head1 DESCRIPTION

Ubic::AccessGuard sets effective uid to specified service's user id if neccesary, and restore it back on destruction.

It's usage is limited, because when effective uid is not equal to real uid, perl automatically turns on tainted mode.
Because of this, only tainted-safe code should be called when AccessGuard is active.
L<Ubic> doesn't start services under this guard, but uses it when acquiring locks and writing service status files.

=head1 METHODS

=over

=cut

use Params::Validate;
use Ubic::Result qw(result);
use Ubic::Credentials;
use Carp;
use Scalar::Util qw(weaken);
use Try::Tiny;

# AccessGuard is actually a singleton - there can't be two guards for two different services, because process can't have two euids.
# So we keep weakref to any created AccessGuard.
my $ag_ref;

=item C<< new($service) >>

Construct new access guard object.

User will be changed into user apporpriate for running C<$service>. It will be changed back on guard's desctruction.

=cut

sub new {
    my $class = shift;
    my ($service) = validate_pos(@_, { isa => 'Ubic::Service' });

    if ($ag_ref) {
        # oops, another AccessGuard already exists
        my $ag = $$ag_ref;
        if ($ag->{service_name} eq $service->full_name) {
            # it's for the same service, ok
            return $ag;
        }
        else {
            croak "Can't create AccessGuard for ".$service->full_name.", there is already another AccessGuard for ".$ag->{service_name};
        }
    }

    my $creds = Ubic::Credentials->new(service => $service);

    my $self = bless {
        service_name => $service->full_name,
        creds => $creds,
    } => $class;

    try {
        $creds->set_effective;
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

    $self->{creds}->reset_effective;
}

=back

=cut

1;
