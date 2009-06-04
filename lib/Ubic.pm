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

use Params::Validate qw(:all);
use Carp;
use Perl6::Slurp;
use File::Basename;
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
    my $params = validate(@_, {
        watchdog_dir => { type => SCALAR, default => $ENV{UBIC_WATCHDOG_DIR} || "/var/lib/ubic/watchdog" },
        service_dir =>  { type => SCALAR, default => $ENV{UBIC_SERVICE_DIR} || "/etc/ubic/service" },
        lock_dir =>  { type => SCALAR, default => $ENV{UBIC_LOCK_DIR} || "/var/lib/ubic/lock" },
    });
    return bless {%$params, locks => {}} => $class;
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

sub lock($$) {
    my ($self) = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    $self->{locks}{$name} ||= xopen(">>$self->{lock_dir}/$name");
    return lockf($self->{locks}{$name});
}

=item B<enable>

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

=item B<is_enabled>

Returns true value if service is enabled, false otherwise.

=cut
sub is_enabled($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    return (-e $self->watchdog_file($name)); # watchdog presence means service is running or should be running
}

=item B<disable>

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

=item B<start>

Start service by name.

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

=item B<stop>

Stop service by name.

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

=item B<restart>

Restart service by name.

=cut
sub restart($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return 'down';
    }
    my $result = $self->service($name)->restart;
    return $result;
}

=item B<status>

Get service status by name.

=cut
sub status($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    $self->service($name)->status;
}

=item B<cached_status>

Get cached status of enabled service.

=cut
sub cached_status($$) {
    my ($self) = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return 'disabled';
    }
    return $self->watchdog($name)->{status};
}

=item B<service>

Get service by name.

=cut
sub service($$) {
    my $self = obj(shift);
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    # no lock - service's construction should be harmless

    my $file = "$self->{service_dir}/$name";
    if (-e $file) {
        my $content = slurp($file);
        $content = "# line 1 $file\n$content";
        my $service = eval $content;
        if ($@) {
            die "Failed to eval '$file': $@";
        }
        unless (defined $service->name) {
            $service->name($name);
        }
        return $service;
    }
    else {
        croak "Service '$name' not found";
    }
}

=item B<services>

Get list of all services.

=cut
sub services($) {
    my $self = obj(shift);

    my @services;
    for my $file (glob("$self->{service_dir}/*")) {
        # TODO - can $self->{service_dir} contain any subdirs?
        $file = basename($file);
        push @services, $self->service($file);
    }
    return @services;
}

sub set_cached_status($$$) {
    my $self = obj(shift);
    my ($name, $status) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/}, {type => SCALAR});
    my $lock = $self->lock($name);

    my $watchdog = $self->watchdog($name);
    $watchdog->{status} = $status;
    $watchdog->commit;
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

