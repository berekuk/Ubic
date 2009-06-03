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
use Ubic::Catalog;

=item B<name>

Name of service.

Each service should have an unique name.

=cut
sub name {
    croak "name() not implemented";
}

=cut

=item B<start>

Start service. Should throw exception on failure and string with operation result otherwise.

Starting already running service should do nothing and return "already running".

Successful start of a service B<must> enable this service.

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

=item B<enable>

Enable service.

Enabled service means that service *should* be running. It will be checked by watchdog and marked as broken if it's enabled but not running.

=cut
sub enable {
    my ($self) = @_;
    Ubic::Catalog->enable($self->name);
}

=item B<disable>

Disable service.

Disabled service means that service is ignored by ubic. It's state will no longer be checked by watchdog, and pings will answer that service is not running, even if it's not true.

=cut
sub disable {
    my ($self) = @_;
    Ubic::Catalog->disable($self->name);
}

=item B<is_enabled>

Returns true value if service is enabled, false otherwise.

=cut
sub is_enabled {
    my ($self) = @_;
    Ubic::Catalog->is_enabled($self->name);
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

