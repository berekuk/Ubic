package Ubic::Service::Skeleton;

use strict;
use warnings;

=head1 NAME

Ubic::Service::Skeleton - skeleton of any service with common start/stop logic

=cut

use Yandex::Lockf;
use Ubic::Result qw(result);
use Scalar::Util qw(blessed);

use base qw(Ubic::Service);

=head1 ACTIONS

=over

=item B<< status() >>

Get status of service.

Possible values: C<running>, C<not running>, C<unknown>, C<broken>.

=cut
sub status {
    my ($self) = @_;
    my $result = $self->status_impl;
    $result ||= 'unknown';
    $result = result($result);
    return $result;
}

=item B<< start() >>

Start service.

Throws exception on failure.

=cut
sub start {
    my ($self) = @_;

    my $status = $self->status;
    if ($status->status eq 'running') {
        return 'already running'; # TODO - update $status field instead?
    }
    elsif ($status->status eq 'not running') {
        return $self->_do_start;
    }
    elsif ($status->status eq 'broken') {
        # checks inside _do_start and _do_stop guarantee correct status
        $self->_do_stop;
        return $self->_do_start;
    }
    else {
        die result('unknown', "wrong status '$status'");
    }
}

=item B<< stop() >>

Stop service.

Return values: C<stopped>, C<not running>.

Throws exception on failure.

=cut
sub stop {
    my ($self) = @_;

    my $status = $self->status;
    if ($status->status eq 'not running') {
        return 'not running';
    }

    return $self->_do_stop;
}

=back

=head1 OVERLOADABLE METHODS

Subclass must overload following methods with simple status, start and stop implementations.

=over

=item I<status_impl>

Status implentation. Should return result object or plain string which coerces to result object.

=cut
sub status_impl {
    die 'not implemented';
}

=item I<start_impl>

Start implentation. It shouldn't check for current status, this base class will care about it itself.

Return value will be ignored.

=cut
sub start_impl {
    die 'not implemented';
}

=item I<stop_impl>

Stop implentation. It shouldn't check for current status, this base class will care about it itself.

Return value will be ignored.

=cut
sub stop_impl {
    die 'not implemented';
}

=back

=cut

##### internal methods ######

sub _do_start {
    my ($self) = @_;

    my $status;

    my $start_result = $self->start_impl;
    if (blessed($start_result) and $start_result->isa('Ubic::Result::Class')) {
        $status = $start_result;
    }
    else {
        $status = $self->status;
    }

    if ($status->status eq 'running') {
        return 'started';
    }
    else {
        die result($status, 'start failed');
    }
}

sub _do_stop {
    my ($self) = @_;
    my $status;

    my $stop_result = $self->stop_impl;
    if (blessed($stop_result) and $stop_result->isa('Ubic::Result::Class')) {
        $status = $stop_result; # stop_impl can return status, in this case we don't want to recheck it
    }
    else {
        $status = $self->status;
        $status->type('stopped');
    }

    if ($status->status eq 'not running') {
        return $status;
    }
    else {
        die result($status, 'stop failed');
    }
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

