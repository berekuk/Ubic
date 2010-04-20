package Ubic::AccessGuard;

use strict;
use warnings;

=head1 NAME

Ubic::AccessGuard - class which guards all service operations

=head1 SYNOPSIS

    use Ubic::AccessGuard;

    $guard = Ubic::AccessGuard->new($service); # take lock under $service->user
    undef $guard; # free lock

=head1 DESCRIPTION

Ubic::AccessGuard sets effective uid to specified service's user id if neccesary, and restore it back on destruction.

It's usage is limited, because when effective uid is not equal to real uid, perl automatically turns on tainted mode. Because of this, only tainted-safe code should be called when AccessGuard is active. L<Ubic> doesn't start services under this guard, only takes locks and writes status files.

=head1 METHODS

=over

=cut

use Params::Validate;
use Ubic::Result qw(result);
use Carp;
use Scalar::Util qw(weaken);

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

    my $user = $service->user;
    my $current_user = getpwuid($>);

    my $self = bless {
        old_euid => $>,
        service_name => $service->full_name,
    } => $class;

    if ($user ne $current_user) {
        if ($current_user ne 'root') {
            die result('unknown', "You are $current_user, and service ".$service->name." should be started from $user");
        }
        my $new_uid = getpwnam($user);
        unless (defined $new_uid) {
            die "user $user not found";
        }
        $> = $new_uid;
        if ($> != $new_uid) {
            die result('unknown', "Failed to change user from $> to $new_uid: $!");
        }
    }

    $ag_ref = \$self;
    weaken($ag_ref);

    return $self;
}

sub DESTROY {
    my $self = shift;

    if ($> != $self->{old_euid}) {
        $> = $self->{old_euid}; # return euid back to normal
        if ($> != $self->{old_euid}) {
            die result('unknown', "Failed to restore euid from $> to $self->{old_euid}: $!");
        }
    }
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

