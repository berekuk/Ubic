package Ubic::Service;

use strict;
use warnings;

=head1 NAME

Ubic::Service - interface and base class for any ubic service

=head1 SYNOPSIS

    print "Service: ", $service->name;
    $service->start;
    $service->stop;
    $service->restart;
    $status = $service->status;

=head1 METHODS

=over

=cut

use Carp;
use Ubic;

=item B<name>

Name of service.

Each service should have an unique name.

=cut
sub name($;$) {
    my ($self, $name) = @_;
    if (defined $name) {
        $self->{name} = $name;
    }
    else {
        return $self->{name};
    }
}

=cut

=item B<start>

Start service. Should throw exception on failure and string with operation result otherwise.

Starting already running service should do nothing and return "already running".

=cut
sub start {
    die "not implemented";
}

=item B<stop>

Stop service. Should throw exception on failure and string with operation result otherwise.

Stopping already stopped service should do nothing and return "not running".

Successful stop of a service B<must> disable this service.

=cut
sub stop {
    die "not implemented";
}

=item B<status>

Check real status of service.

It should check that service is running correctly and return "running" if it is so.

=cut
sub status {
    my ($self) = @_;
    die "not implemented";
}

sub restart {
    my ($self) = @_;
    $self->stop;
    return $self->start; # FIXME!
}

=item B<port>

Should return port number if service provides a server which uses TCP protocol.

=cut
sub port {
    my ($self) = @_;
    return; # by default, service has no port
    # TODO - what will this method return when complex services which runs several daemons at once will be implemented?
}

=item B<check_period>

Returns period of checking a service by watchdog in seconds.

=cut
sub check_period {
    my ($self) = @_;
    return 60;
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

