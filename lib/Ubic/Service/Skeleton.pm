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
        return $self->do_start;
    } elsif ($status eq 'broken') {
        # checks inside do_start and do_stop guarantee correct status
        $self->do_stop;
        return $self->do_start;
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

    $self->do_stop;
    # TODO - check status
    return 'stopped';
}

=back

=cut

##### internal methods ######

sub do_start {
    my ($self) = @_;
    $self->start_impl;
    my $status = $self->status;
    if ($status eq 'running') {
        return 'started';
    } else {
        die "start failed, status: '$status'";
    }
}

sub do_stop {
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

# methods which must be overloaded

sub status_impl {
    die 'not implemented';
}

sub start_impl {
    die 'not implemented';
}

sub stop_impl {
    die 'not implemented';
}


=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

