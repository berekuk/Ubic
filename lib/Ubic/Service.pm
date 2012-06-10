package Ubic::Service;

use strict;
use warnings;

use Ubic::Settings;

# ABSTRACT: interface and the base class for any ubic service

=head1 SYNOPSIS

    print "Service: ", $service->name;
    $service->start;
    $service->stop;
    $service->restart;
    $status = $service->status;

=cut

use Ubic::Result qw(result);

=head1 DESCRIPTION

C<Ubic::Service> is the abstract base class for all ubic service classes.

It provides the common API for implementing start/stop/status operations, custom commands and tuning some metadata properties (C<user()>, C<group()>, C<check_period()>).

=head1 METHODS

=head2 ACTION METHODS

All action methods should return L<Ubic::Result::Class> objects. If action method returns a plain string, L<Ubic> will wrap it into result object for you.

=over

=item B<start()>

Start the service. Should throw an exception on failure and a result object or a string with operation result otherwise.

Starting an already running service should do nothing and return C<already running>.

=cut
sub start {
    die "not implemented";
}

=item B<stop()>

Stop the service. Should throw an exception on failure and a result object or a string with operation result otherwise.

Stopping an already stopped service should do nothing and return C<not running>.

Successful stop of a service B<must> disable this service.

=cut
sub stop {
    die "not implemented";
}

=item B<status()>

Check the status of the service.

It should check that service is running correctly and return C<running> if it is so.

=cut
sub status {
    my ($self) = @_;
    die "not implemented";
}

=item B<reload()>

Reload the service if possible.

Throw an exception if reloading is not implemented (default implementation already does so).

=cut
sub reload {
    my ($self) = @_;
    return result('unknown', 'not implemented');
}

=back

=head2 METADATA METHODS

All metadata methods are read-only. All of them provide the sane defaults.

=over

=item B<port()>

Get the port number if a service listens for a TCP port.

Default is C<undef>.

=cut
sub port {
    my ($self) = @_;
    return; # by default, service has no port
}

=item B<user()>

Get the user from which the service can be controlled and will be running.

Defaults to I<default_user> from L<Ubic::Settings> (i.e., C<root> for a system-wide installation, or to the installation owner for a local installation).

=cut
sub user {
    my $self = shift;
    return Ubic::Settings->default_user;
}

=item B<group()>

Get the list of groups from which the service can be controlled and will be running.

First group from the list will be used as real and effective group id, and other groups will be set as supplementary groups.

Default is an empty list, which will later be interpreted as default group of the user returned by C<user()> method.

=cut
sub group {
    return ();
}

=item B<check_period()>

Period of checking a service by watchdog in seconds.

Default is 60 seconds and it is unused by the B<ubic.watchdog> currently, so don't bother to override it by now :)

=cut
sub check_period {
    my ($self) = @_;
    return 60;
}

=item B<check_timeout()>

Timeout after which the watchdog will give up on checking the service and will kill itself.

This parameter exists as a precaution against incorrectly implemented C<status()> or C<start()> methods.
If a C<status()> method hangs, without this timeout, watchdog would stay in memory forever and never get a chance to restart a service.

This parameter is B<not> a timeout for querying your service by HTTP or whatever your status check is. Service-specific timeouts should be configured by other means.

Default value is 60 seconds. It should not be changed unless you have a very good reason to do so (i.e., your service is so horribly slow that it can't start in 1 minute).

=cut
sub check_timeout {
    return 60;
}

=back

=head2 CUSTOM COMMAND METHODS

Services can define custom commands which don't fit into the usual C<start/stop/restart/status> set.

=over

=item B<custom_commands()>

Get the list of service's custom commands, if there are any.

=cut
sub custom_commands {
    return ();
}

=item B<do_custom_command($command)>

Execute specified command, if it is supported. Throw an exception otherwise.

=cut
sub do_custom_command {
    die "No such command";
}

=back

=head2 NAME METHODS

These methods should not be overriden by specific service classes.
They are usually used by the code which loads service (i.e. some kind of L<Ubic::Multiservice>) to associate service with its name.

These methods are just the simple interdependent r/w accessors.

=over

=item B<name()>

=item B<name($new_name)>

Get or set a name of the service.

Each service with the same parent should have an unique name.

In case of subservices, this method should return the most lower-level name.

Service implementation classes shouldn't override this or other C<*_name> methods; it's usually a service's loader job to set them correctly.

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

=item B<full_name()>

Get a fully qualified name of the service.

Each service must have a unique full_name.

Full name is a concatenation of service's short C<name> and service's <parent_name>.

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

Get or set a name of the service's parent.

Service's loader (i.e. some kind of L<Ubic::Multiservice>) is responsible for calling this method immediately after a service is constructed, like this: C<< $service->parent_name($self->full_name) >> (check out L<Ubic::Multiservice> sources for more).

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

=back

=head1 FUTURE DIRECTIONS

Current API for custom commands is inconvenient and doesn't support parameterized commands. It needs some refactoring.

Requiring every service to inherit from this class can be seen as undesirable by some programmers, especially by those who prefer to use Moose and roles.
If you know how to make this API more role-friendly without too much of converting pains, please contact us at ubic-perl@googlegroups.com or at irc://irc.perl.org#ubic.

=head1 SEE ALSO

L<Ubic::Service::Skeleton> - implement simple start/stop/status methods, and ubic will care about everything else.

L<Ubic::Service::Common> - just like Skeleton, but all code can be passed to constructor as sub references.

L<Ubic::Service::SimpleDaemon> - give it any binary and it will make a service from it.

=cut

1;
