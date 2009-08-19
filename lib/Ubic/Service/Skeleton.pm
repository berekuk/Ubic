package Ubic::Service::Skeleton;

use strict;
use warnings;

=head1 NAME

Ubic::Service::Skeleton - skeleton of any service with common start/stop logic

=cut

use Yandex::Lockf;

use base qw(Ubic::Service);

=head1 ACTIONS

=over

=item C<status>

Get status of service.

Possible values: C<running>, C<not running>, C<unknown>, C<broken>.

=cut
sub status {
    my ($self) = @_;
    my $status = $self->status_impl;
    $status ||= 'unknown';
    return $status;
}

=item C<start>

Start service.

Throws exception on failure.

=cut
sub start {
    my ($self) = @_;

    my $status = $self->status;
    if ($status eq 'running') {
        return 'already running';
    } elsif ($status eq 'not running') {
        return $self->_do_start;
    } elsif ($status eq 'broken') {
        # checks inside _do_start and _do_stop guarantee correct status
        $self->_do_stop;
        return $self->_do_start;
    } else {
        die "Unknown status '$status'";
    }
}

=item C<stop>

Stop service.

Return values: C<stopped>, C<not running>.

Throws exception on failure.

=cut
sub stop {
    my ($self) = @_;

    my $status = $self->status;
    if ($status eq 'not running') {
        return 'not running';
    }

    $self->_do_stop;
    # TODO - check status
    return 'stopped';
}

=back

=head1 OVERLOADABLE METHODS

Subclass must overload following methods with simple status, start and stop implementations.

=over

=item I<status_impl>

Status implentation.

=cut
sub status_impl {
    die 'not implemented';
}

=item I<start_impl>

Start implentation. It shouldn't check for current status, this base class will care about it itself.

=cut
sub start_impl {
    die 'not implemented';
}

=item I<stop_impl>

Stop implentation. It shouldn't check for current status, this base class will care about it itself.

=cut
sub stop_impl {
    die 'not implemented';
}

=back

=cut

##### internal methods ######

sub _do_start {
    my ($self) = @_;
    $self->start_impl;
    my $status = $self->status;
    if ($status eq 'running') {
        return 'started';
    } else {
        die "start failed, status: '$status'";
    }
}

sub _do_stop {
    my ($self) = @_;
    $self->stop_impl;
    my $status = $self->status;
    if ($status eq 'not running') {
        return 'stopped';
    }
    else {
        die "stop failed, current status: '$status'";
    }
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

