package Ubic::AccessGuard;

use strict;
use warnings;

=head1 NAME

Ubic::AccessGuard - class which guards all service operations

=head1 SYNOPSIS

    use Ubic::AccessGuard;

    $guard = Ubic::AccessGuard->new($service); # take lock under $service->user
    undef $guard; # free lock

=head1 METHODS

=over

=cut

use Params::Validate;
use Ubic::Result qw(result);

=item C<< new($service) >>

Construct new access guard object.

User will be changed into user apporpriate for running C<$service>. It will be changed back on guard's desctruction.

=cut
sub new {
    my $class = shift;
    my ($service) = validate_pos(@_, { isa => 'Ubic::Service' });

    my $user = $service->user;
    my $current_user = getpwuid($>);

    my $self = bless {
        old_uid => $<, # why do we care about real uid?
        old_euid => $>,
    } => $class;

    if ($user ne $current_user) {
        if ($current_user ne 'root') {
            die result('unknown', "You are $current_user, and service ".$service->name." should be started from $user");
        }
        my $new_uid = getpwnam($user);
        $> = $new_uid;
        if ($!) {
            die result('unknown', "Failed to change user from $> to $new_uid: $!");
        }
    }

    return $self;
}

sub DESTROY {
    my $self = shift;

    if ($< != $self->{old_uid} or $> != $self->{old_euid}) {
        ($<, $>) = ($self->{old_uid}, $self->{old_euid}); # return uids back to normal
        if ($!) {
            die result('unknown', "Failed to restore uids: $!");
        }
    }
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

