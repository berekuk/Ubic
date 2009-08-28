package Ubic;

use strict;
use warnings;

use Yandex::Version '{{DEBIAN_VERSION}}';

=head1 NAME

Ubic - frontend to all ubic services

=head1 SYNOPSIS

    Ubic->start("yandex-something");

    Ubic->stop("yandex-something");

    $status = Ubic->status("yandex-something");

=head1 DESCRIPTION

Ubic allows you to implement safe services which will be monitored and checked automatically.

This module is a main frontend to ubic services.

Further directions:

if you want to manage ubic services from perl scripts, read this POD;

if you want to use ubic from command line, see L<ubic(1)> and L<Ubic::Cmd>.

if you want to write your own service, see L<Ubic::Service> and other C<Ubic::Service::*> modules. Check out L<Ubic::Run> for integration with SysV init script system too.

=cut

use Ubic::Result qw(result);
use Ubic::AccessGuard;
use Ubic::Catalog::Dir;
use Params::Validate qw(:all);
use Carp;
use Yandex::Persistent;
use Yandex::Lockf;
use Yandex::X qw(xopen);
use Scalar::Util qw(blessed);

our $SINGLETON;

# singleton constructor
sub _obj {
    my ($param) = validate_pos(@_, 1);
    if (blessed($param)) {
        return $param;
    }
    if ($param eq 'Ubic') {
        # method called as a class method => singleton
        $SINGLETON ||= Ubic->new({});
        return $SINGLETON;
    }
    die "Unknown argument '$param'";
}

=head1 CONSTRUCTOR

=over

=item B<< Ubic->new({ ... }) >>

All methods in this package can be invoked as class methods, but sometimes you may need to override some status dirs. In this case you should construct your own instance.

Constructor options (all of them are optional):

=over

=item I<watchdog_dir>

Dir with persistent services' watchdogs.

=item I<service_dir>

Name of dir with service descriptions (for root services catalog's namespace).

=item I<lock_dir>

Dir with services' locks.

=back

=cut
sub new {
    my $class = shift;
    my $self = validate(@_, {
        watchdog_dir => { type => SCALAR, default => $ENV{UBIC_WATCHDOG_DIR} || "/var/lib/ubic/watchdog" },
        service_dir =>  { type => SCALAR, default => $ENV{UBIC_SERVICE_DIR} || "/etc/ubic/service" },
        lock_dir =>  { type => SCALAR, default => $ENV{UBIC_LOCK_DIR} || "/var/lib/ubic/lock" },
    });
    $self->{locks} = {};
    $self->{root} = Ubic::Catalog::Dir->new($self->{service_dir});
    return bless $self => $class;
}

=back

=head1 LSB METHODS

See L<http://refspecs.freestandards.org/LSB_3.1.0/LSB-Core-generic/LSB-Core-generic/iniscrptact.html> for init-script method specifications.

Following functions are trying to conform, except that all dashes in method names are replaced with underscores.

Unlike C<Ubic::Service> methods, these methods are guaranteed to return blessed versions of result, i.e. C<Ubic::Result::Class> objects.

=over

=item B<start($name)>

Start service.

=cut
sub start($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $access = Ubic::AccessGuard->new($self->service($name));
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->do_cmd($name, 'start');
    if ($result->status eq 'running') {
        $self->set_cached_status($name, 'running');
    }
    return $result;
}

=item B<stop($name)>

Stop service.

=cut
sub stop($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $access = Ubic::AccessGuard->new($self->service($name));
    my $lock = $self->lock($name);

    $self->disable($name);
    my $result = $self->do_cmd($name, 'stop');
    # we can't save result in watchdog file - it doesn't exist when service is disabled...
    return $result;
}

=item B<restart($name)>

Restart service; start it if it's not running.

=cut
sub restart($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $access = Ubic::AccessGuard->new($self->service($name));
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->do_cmd($name, 'stop');
    $result = $self->do_cmd($name, 'start');

    if ($result->status eq 'running') {
        $self->set_cached_status($name, 'running');
    }
    return result('restarted'); # FIXME - should return original status
}

=item B<try_restart($name)>

Restart service if it is enabled.

=cut
sub try_restart($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $access = Ubic::AccessGuard->new($self->service($name));
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return result('down');
    }
    $self->do_cmd($name, 'stop');
    $self->do_cmd($name, 'start');
    return result('restarted');
}

=item B<reload($name)>

Reloads service if reloading is implemented; throw exception otherwise.

=cut
sub reload($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $access = Ubic::AccessGuard->new($self->service($name));
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return result('down');
    }

    # if reload isn't implemented, do nothing
    # TODO - would it be better to execute reload as force-reload always? but it would be incompatible with LSB specification...
    my $result = $self->do_cmd($name, 'reload');
    unless ($result->action eq 'restarted') {
        die result('unknown', 'reload not implemented');
    }
    return $result;
}

=item B<force_reload($name)>

Reloads service if reloading is implemented, otherwise restarts it.

Does nothing if service is disabled.

=cut
sub force_reload($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $access = Ubic::AccessGuard->new($self->service($name));
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return result('down');
    }

    my $result = $self->do_cmd($name, 'reload');
    return $result if $result->action eq 'restarted';

    $self->try_restart($name);
}

=item B<status($name)>

Get service status.

=cut
sub status($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $lock = $self->lock($name);

    return $self->do_cmd($name, 'status');
}

=back

=head1 OTHER METHODS

=over

=item B<enable($name)>

Enable service.

Enabled service means that service *should* be running. It will be checked by watchdog and marked as broken if it's enabled but not running.

=cut
sub enable($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $lock = $self->lock($name);

    my $watchdog = $self->watchdog($name);
    $watchdog->{status} = 'unknown';
    $watchdog->commit;
    return result('unknown');
}

=item B<is_enabled($name)>

Returns true value if service is enabled, false otherwise.

=cut
sub is_enabled($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);

    die "Service '$name' not found" unless $self->{root}->has_service($name);
    return (-e $self->watchdog_file($name)); # watchdog presence means service is running or should be running
}

=item B<disable($name)>

Disable service.

Disabled service means that service is ignored by ubic. It's state will no longer be checked by watchdog, and pings will answer that service is not running, even if it's not true.

=cut
sub disable($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    my $lock = $self->lock($name);

    if ($self->is_enabled($name)) {
        unlink $self->watchdog_file($name) or die "Can't unlink '".$self->watchdog_file($name)."'";
    }
}


=item B<cached_status($name)>

Get cached status of enabled service.

Unlike other methods, it doesn't require user to be root.

=cut
sub cached_status($$) {
    my ($self) = _obj(shift);
    my ($name) = validate_pos(@_, 1);

    unless ($self->is_enabled($name)) {
        return result('disabled');
    }
    return result($self->watchdog_ro($name)->{status});
}

=item B<service($name)>

Get service _object by name.

=cut
sub service($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+(?:\.[\w-]+)*$} }); # this guarantees that : will be unambiguous separator in watchdog filename
    return $self->{root}->service($name);
}

=item B<services()>

Get list of all services.

=cut
sub services($) {
    my $self = _obj(shift);
    return $self->{root}->services();
}

=item B<service_names()>

Get list of names of all services.

=cut
sub service_names($) {
    my $self = _obj(shift);
    return $self->{root}->service_names();
}

=item B<root_service()>

Get root service.

Root service doesn't have a name and returns all top-level services with C<services()> method. You can use it to traverse all services' tree.

=cut
sub root_service($) {
    my $self = _obj(shift);
    return $self->{root};
}

=item B<compl_services($line)>

Return list of autocompletion variants for given service prefix.

=cut
sub compl_services($$) {
    my $self = _obj(shift);
    my $line = shift;
    my @parts = split /\./, $line;
    if (@parts == 0) {
        return $self->service_names;
    }
    my $node = $self->root_service;
    while (@parts > 1) {
        my $part = shift @parts;
        return unless $node->has_service($part); # no such service
        $node = $node->service($part);
    }
    my @variants = $node->service_names;
    return grep { $_ =~ m{^\Q$line\E} } @variants;
}

=item B<set_cached_status($name, $status)>

Write new status into service's watchdog status file.

=cut
sub set_cached_status($$$) {
    my $self = _obj(shift);
    my ($name, $status) = validate_pos(@_, 1, 1);
    if (blessed $status) {
        croak "Wrong status param '$status'" unless $status->isa('Ubic::Status::Class');
        $status = $status->status;
    }
    my $lock = $self->lock($name);

    my $watchdog = $self->watchdog($name);
    $watchdog->{status} = $status;
    $watchdog->commit;
}

=back

=head1 INTERNAL METHODS

You don't need to call these, usually.

=over

=item B<watchdog_file($name)>

Get watchdog file name by service's name.

=cut
sub watchdog_file($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+(?:\.[\w-]+)*$} });
    return "$self->{watchdog_dir}/".$name;
}

=item B<watchdog($name)>

Get watchdog persistent object by service's name.

=cut
sub watchdog($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    return Yandex::Persistent->new($self->watchdog_file($name));
}

=item B<watchdog_ro($name)>

Get readonly, nonlocked watchdog persistent object by service's name.

=cut
sub watchdog_ro($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, 1);
    return Yandex::Persistent->new($self->watchdog_file($name), {lock => 0}); # lock => 0 should allow to construct persistent even without writing rights on it
}

=item B<lock($name)>

Lock given service.

=cut
sub lock($$) {
    my ($self) = _obj(shift);
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+(?:\.[\w-]+)*$} });
    $self->{locks}{$name} ||= xopen(">>", $self->{lock_dir}."/".$name);
    return lockf($self->{locks}{$name});
}

=item B<< do_sub($code) >>

Run any code and wrap result into C<Ubic::Result::Class> object.

=cut
sub do_sub($$) {
    my ($self, $code) = @_;
    my $result = eval {
        $code->();
    }; if ($@) {
        die result($@);
    }
    return result($result);
}

=item B<< do_cmd($name, $cmd) >>

Run C<$cmd> method from service C<$name> and wrap result into C<Ubic::Result::Class> object.

=cut
sub do_cmd($$$) {
    my ($self, $name, $cmd) = @_;
    $self->do_sub(sub {
        $self->service($name)->$cmd()
    });
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

