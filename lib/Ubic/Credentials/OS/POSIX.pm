package Ubic::Credentials::OS::POSIX;

use strict;
use warnings;

use parent qw(Ubic::Credentials);

# ABSTRACT: POSIX-specific credentials implementation

=head1 METHODS

=over

=cut

use List::MoreUtils qw(uniq);

use Params::Validate qw(:all);
use Carp;

sub new {
    my $class = shift;
    my $params = validate(@_, {
        user => 0,
        group => 0,
        service => { optional => 1, isa => 'Ubic::Service' },
    });

    my $self = {};
    if (defined $params->{user}) {
        if (defined $params->{service}) {
            croak "Only one of 'user' and 'service' parameters should be specified";
        }
        $self->{user} = $params->{user};
        $self->{group} = $params->{group} if defined $params->{group};
    }
    elsif (defined $params->{service}) {
        $self->{user} = $params->{service}->user;
        my @group = $params->{service}->group;
        $self->{group} = [ @group ] if @group;
    }
    else {
        $self->{real_user_id} = $<;
        $self->{effective_user_id} = $>;
        $self->{real_group_id} = [ split / /, $( ];
        $self->{effective_group_id} = [ split / /, $) ];
        # TODO - derive user from real_user_id when user is not specified (or from effective_user_id?!)
    }

    return bless $self => $class;
}

=item B<< user() >>

Get user name.

=cut
sub user {
    my $self = shift;
    unless (defined $self->{user}) {
        $self->{user} = getpwuid($>);
    }
    return $self->{user};
}

=item B<< group() >>

Get list of group names.

=cut
sub group {
    my $self = shift;
    unless (defined $self->{group}) {
        $self->_user2group;
    }
    unless (ref $self->{group}) {
        $self->{group} = [ $self->{group} ];
    }
    return @{ $self->{group} };
}

sub _user2uid {
    my $self = shift;
    my $user = $self->user;
    my $id = scalar getpwnam($user);
    unless (defined $id) {
        croak "user $user not found";
    }
    return $id;
}

=item B<< real_user_id() >>

Get numeric real user id.

=cut
sub real_user_id {
    my $self = shift;
    return $self->{real_user_id} if defined $self->{real_user_id};
    return $self->_user2uid;
}

=item B<< effective_user_id() >>

Get numeric effective user id.

=cut
sub effective_user_id {
    my $self = shift;
    return $self->{effective_user_id} if defined $self->{effective_user_id};
    return $self->_user2uid;
}

sub _group2gid {
    my $self = shift;
    my @group = $self->group;
    my @gid;
    for my $group (@group) {
        my $gid = getgrnam($group);
        unless (defined $gid) {
            croak "group $group not found";
        }
        push @gid, $gid;
    }
    @gid = (@gid, @gid) if @gid == 1; # otherwise $) = "1 0"; $) = "1" leaves 0 in group list
    return @gid;
}

=item B<< real_group_id() >>

Get numeric real group id.

=cut
sub real_group_id {
    my $self = shift;
    return @{ $self->{real_group_id} } if defined $self->{real_group_id};
    return $self->_group2gid;
}

=item B<< effective_group_id() >>

Get numeric effective group id.

=cut
sub effective_group_id {
    my $self = shift;
    return @{ $self->{effective_group_id} } if defined $self->{effective_group_id};
    return $self->_group2gid;
}

sub _user2group {
    my $self = shift;
    my $user = $self->user;
    confess "user not defined" unless defined $user;

    my $main_group = getgrgid((getpwnam $user)[3]);
    setgrent();
    my @groups;
    while (my @grent = getgrent()) {
        my @users = split / /, $grent[3];
        push @groups, $grent[0] if grep { $_ eq $user } @users;
    }
    endgrent();
    $self->{group} = [ $main_group, @groups ];
}

sub set_effective {
    my $self = shift;

    my $current_creds = Ubic::Credentials->new;
    my $euid = $current_creds->effective_user_id();
    my ($egid) = $current_creds->effective_group_id();
    $egid =~ s/^(\d+).*/$1/;

    my $current_user = getpwuid($euid);
    my $current_group = getgrgid($egid);

    my $user = $self->user;
    my ($group) = $self->group;

    if ($group ne $current_group) {
        $self->{old_egid} = $);
        my $new_gid = getgrnam($group);
        unless (defined $new_gid) {
            die "group $group not found";
        }

        # AccessGuard don't need to handle supplementary groups correctly, so this is ok
        $) = "$new_gid 0";
        my ($current_gid) = $) =~ /^(\d+)/;
        if ($current_gid != $new_gid) {
            die "Failed to change group from $group to $current_group: $!";
        }
    }

    if ($user ne $current_user) {
        $self->{old_euid} = $>;
        if ($current_user ne 'root') {
            die "Can't change user from $current_user to $user";
        }
        my $new_uid = getpwnam($user);
        unless (defined $new_uid) {
            die "user $user not found";
        }
        $> = $new_uid;
        if ($> != $new_uid) {
            die "Failed to change user from $current_user to $user: $!";
        }
    }
}

sub _groups_equal {
    my ($self, $g1, $g2) = @_;
    my ($main1, @other1) = split / /, $g1;
    my ($main2, @other2) = split / /, $g2;
    return ($main1 == $main2 and join(' ', sort { $a <=> $b } uniq($main1, @other1)) eq join(' ', sort { $a <=> $b } uniq($main2, @other2)));
}


sub reset_effective {
    my $self = shift;

    if (defined $self->{old_euid}) {
        $> = $self->{old_euid}; # return euid back to normal
        if ($> != $self->{old_euid}) {
            warn "Failed to restore euid from $> to $self->{old_euid}: $!";
        }
    }
    if (defined $self->{old_egid}) {
        $) = $self->{old_egid}; # return egid back to normal
        if ($) != $self->{old_egid}) {
            warn "Failed to restore egid from '$)' to '$self->{old_egid}': $!";
        }
    }
}

sub eq {
    my ($self, $other) = @_;
    if (
        $self->effective_user_id == $other->effective_user_id()
        and $self->real_user_id == $other->real_user_id()
        and $self->_groups_equal($self->effective_group_id, $other->effective_group_id())
        and $self->_groups_equal($self->real_group_id, $other->real_group_id())
    ) {
        return 1;
    }
    else {
        return;
    }
}

sub set {
    my ($self) = @_;
    my @effective_gid = $self->effective_group_id;
    $) = "@effective_gid";
    unless ($self->_groups_equal($), "@effective_gid")) {
        die "Failed to set effective gid to @effective_gid: $!";
    }
    my @real_gid = $self->real_group_id;
    $( = $real_gid[0];
    unless ($self->_groups_equal($(, "@real_gid")) {
        die "Failed to set real gid to @real_gid: $!";
    }
    my $new_euid = $self->effective_user_id;
    $> = $new_euid;
    unless ($> == $new_euid) {
        die "Failed to set effective uid to $new_euid: $!";
    }
    my $new_ruid = $self->real_user_id;
    $< = $new_ruid;
    unless ($< == $new_ruid) {
        die "Failed to set real uid to $new_ruid: $!";
    }
}

=back

=head1 BUGS AND CAVEATS

I'm not quite sure this module is POSIX-compatible. It makes use of complementary groups which are probably not implemented on some POSIX-based systems.

It needs to be refactored into separate C<Ubic::Crendentials::OS::POSIX> and C<Ubic::Crendentials::OS::Linux> modules.

=cut

1;
