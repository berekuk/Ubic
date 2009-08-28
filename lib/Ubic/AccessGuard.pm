package Ubic::AccessGuard;

use strict;
use warnings;

=head1 NAME

Ubic::AccessGuard - class for temporarily change effective uid into someone else

=head1 SYNOPSIS

    use Ubic::AccessGuard;

    $guard = Ubic::AccessGuard->new($service); # become $service->user
    undef $guard; # become back who we were

=head1 METHODS

=over

=cut

use Params::Validate;

=item C<< new($service) >>

Construct new access guard object.

User will be changed into user apporpriate for running C<$service>. It will be changed back on guard's desctruction.

=cut
sub new {
    my $class = shift;
    my ($service) = validate_pos(@_, { isa => 'Ubic::Service' });

    my $user = $service->user;
    my $current_user = getpwuid($<);
    my $self = bless {} => $class;

    if ($user ne $current_user) {
        if ($current_user ne 'root') {
            die result('unknown', "You are $current_user, and service ".$service->name." should be started from $user");
        }
        my $new_uid = getpwnam($user);
        $> = $new_uid;
        if ($!) {
            die result('unknown', "Failed to change user from $> to $new_uid: $!");
        }
        $self->{user} = $current_user;
    }

    return $self;
}

sub DESTROY {
    my $self = shift;

    if (exists $self->{user}) {
        my $old_uid = getpwnam($self->{user});
        $> = $old_uid; # return effective id back to normal
        if ($!) {
            die result('unknown', "Failed to change user from $> to $old_uid: $!");
        }
    }
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

