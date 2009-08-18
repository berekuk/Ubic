package Ubic;

use strict;
use warnings;

use Yandex::Version '{{DEBIAN_VERSION}}';

=head1 NAME

Ubic - catalog of all ubic services

=head1 SYNOPSIS

    Ubic->enable("yandex-something");

    Ubic->disable("yandex-something");

    $something_enabled = Ubic->is_enabled("yandex-something");

=cut

use Ubic::Catalog::Dir;
use Params::Validate qw(:all);
use Carp;
use Yandex::Persistent;
use Yandex::Lockf;
use Yandex::X qw(xopen);
use Scalar::Util qw(blessed);

our $SINGLETON;

sub obj {
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

sub new {
    my $class = shift;
    my $self = validate(@_, {
        watchdog_dir => { type => SCALAR, default => $ENV{UBIC_WATCHDOG_DIR} || "/var/lib/ubic/watchdog" },
        service_dir =>  { type => SCALAR, default => $ENV{UBIC_SERVICE_DIR} || "/etc/ubic/service" },
        lock_dir =>  { type => SCALAR, default => $ENV{UBIC_LOCK_DIR} || "/var/lib/ubic/lock" },
    });
    $self->{locks} = {};
    $self->{catalog} = Ubic::Catalog::Dir->new($self->{service_dir});
    return bless $self => $class;
}

sub watchdog_file($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return "$self->{watchdog_dir}/$name";
}

sub watchdog($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return Yandex::Persistent->new($self->watchdog_file($name));
}

sub watchdog_ro($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return Yandex::Persistent->new($self->watchdog_file($name), {lock => 0}); # lock => 0 should allow to construct persistent even without writing rights on it
}

sub lock($$) {
    my ($self) = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    $self->{locks}{$name} ||= xopen(">>$self->{lock_dir}/$name");
    return lockf($self->{locks}{$name});
}

=head1 LSB METHODS

See L<http://refspecs.freestandards.org/LSB_3.1.0/LSB-Core-generic/LSB-Core-generic/iniscrptact.html> for init-script method specifications.

Following functions are trying to conform, except that all dashes in method names are replaced with underscores.

=over

=item B<start($name)>

Start service.

=cut
sub start($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->service($name)->start;
    $self->set_cached_status($name, 'running');
    return $result;
}

=item B<stop($name)>

Stop service.

=cut
sub stop($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    $self->disable($name);
    my $result = $self->service($name)->stop;
    # we can't save result in watchdog file - it doesn't exist when service is disabled...
    return $result;
}

=item B<restart($name)>

Restart service; start it if it's not running.

=cut
sub restart($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    $self->enable($name);
    $self->service($name)->stop;
    $self->service($name)->start;
    $self->set_cached_status($name, 'running');
    return 'restarted';
}

=item B<try_restart($name)>

Restart service if it is enabled.

=cut
sub try_restart($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return 'down';
    }
    $self->service($name)->stop;
    $self->service($name)->start;
    return 'restarted';
}

=item B<reload($name)>

Reloads service if reloading is implemented; throw exception otherwise.

=cut
sub reload($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return 'down';
    }

    # if reload isn't implemented, do nothing
    # TODO - would it be better to execute reload as force-reload always? but it would be incompatible with LSB specification...
    my $reloaded = $self->service($name)->reload;
    unless ($reloaded) {
        die 'reload not implemented';
    }
    return $reloaded;
}

=item B<force_reload($name)>

Reloads service if reloading is implemented, otherwise restarts it.

Does nothing if service is disabled.

=cut
sub force_reload($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return 'down';
    }

    my $reloaded = $self->service($name)->reload;
    return $reloaded if $reloaded;

    $self->try_restart($name);
}

=item B<status($name)>

Get service status.

=cut
sub status($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    $self->service($name)->status;
}

=back

=head1 OTHER METHODS

=over

=item B<enable($name)>

Enable service.

Enabled service means that service *should* be running. It will be checked by watchdog and marked as broken if it's enabled but not running.

=cut
sub enable($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    my $watchdog = $self->watchdog($name);
    $watchdog->{status} = 'unknown';
    $watchdog->commit;
}

=item B<is_enabled($name)>

Returns true value if service is enabled, false otherwise.

=cut
sub is_enabled($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});

    die "Service '$name' not found" unless $self->{catalog}->has_service($name);
    return (-e $self->watchdog_file($name)); # watchdog presence means service is running or should be running
}

=item B<disable($name)>

Disable service.

Disabled service means that service is ignored by ubic. It's state will no longer be checked by watchdog, and pings will answer that service is not running, even if it's not true.

=cut
sub disable($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
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
    my ($self) = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});

    unless ($self->is_enabled($name)) {
        return 'disabled';
    }
    return $self->watchdog_ro($name)->{status};
}

=item B<service($name)>

Get service object by name.

=cut
sub service($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w.-]+(?:/[\w.-]+)*$} }); # this guarantees that : will be unambiguous separator in watchdog filename
    return $self->{catalog}->service($name);
}

=item B<services()>

Get list of all services.

=cut
sub services($) {
    my $self = obj(shift);
    return $self->{catalog}->services();
}

sub set_cached_status($$$) {
    my $self = obj(shift);
    my ($name, $status) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/}, {type => SCALAR});
    my $lock = $self->lock($name);

    my $watchdog = $self->watchdog($name);
    $watchdog->{status} = $status;
    $watchdog->commit;
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

