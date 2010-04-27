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

=cut

use Ubic::Result qw(result);

=head1 DESCRIPTION

All ubic services must be subclasses of this package.

Action methods (like C<start>, C<stop>, C<reload>) and C<status> should return L<Ubic::Result::Class> objects (usually constructed with C<result> method from L<Ubic::Result>).

Or they can return plain strings, L<Ubic> will care about blessing them into result objects.

See L</"SEE ALSO"> for references to more specific (and useful) versions of services.

=head1 METHODS

=over

=cut

=item B<name()>

=item B<name($new_name)>

Name of service.

Each service with the same parent should have an unique name.

In case of subservices, name should be the most lower-level name; use C<full_name> method to get fully-qualified service name.

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

=item B<full_name>

Fully qualified name of service.

Each service should have an unique full_name.

It is a concatenation of service's short C<name> and service's <parent_name>.

Service's parent is responsible for setting it (to concatenation of it's own name and service's name) immediately after service's construction.

In case of subservices, initial name should be the most lower-level name; it will be concatenated with names of it's parents by it's parents. (See L<Ubic::Multiservice>'s code for more details).

=cut
sub full_name($) {
    my ($self) = @_;
    my $parent_name = $self->parent_name;
    if (defined $parent_name) {
        return $parent_name.".".$self->name;
    }
    else {
        return $self->name;
    }
}

=item B<parent_name()>

=item B<parent_name($new_parent_name)>

Get/set name of service's parent.

Service's parent is responsible for calling it immediately after service's construction as C<< $service->parent_name($self->full_name) >>.

=cut
sub parent_name($;$) {
    my ($self, $name) = @_;
    if (defined $name) {
        $self->{parent_name} = $name;
    }
    else {
        return $self->{parent_name};
    }
}

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

=item B<reload>

Reload service, if possible.

=cut
sub reload {
    my ($self) = @_;
    return result('unknown', 'not implemented');
}

=item B<port>

Should return port number if service provides a server which uses TCP protocol.

=cut
sub port {
    my ($self) = @_;
    return; # by default, service has no port
    # TODO - what will this method return when complex services which runs several daemons at once will be implemented?
}

=item B<user>

Should return user from which the service can be controlled and will be running. Default is C<root>.

=cut
sub user {
    my $self = shift;
    return 'root';
}

=item B<check_period>

Should return period of checking a service by watchdog in seconds.

Default is 60 seconds and it is unused by ubic-watchdog currently, so don't bother to override it by now :)

=cut
sub check_period {
    my ($self) = @_;
    return 60;
}

=item B<custom_commands()>

Can return list of service's custom commands, if such are exist.

=cut
sub custom_commands {
    return ();
}

=item B<do_custom_command($command)>

Should execute specified command, if it is supported.

=cut
sub do_custom_command {
    die "No such command";
}

=back

=head1 SEE ALSO

L<Ubic::Service::Skeleton> - implement simple start/stop/status methods, and ubic will care about everything else.

L<Ubic::Service::Common> - just like Skeleton, but all code can be passed to constructor as sub references.

L<Ubic::Service::SimpleDaemon> - just give it any binary and it will make service from it.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

