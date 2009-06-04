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

our $WATCHDOG_DIR = $ENV{UBIC_WATCHDOG_DIR} || "/var/lib/ubic/watchdogs";
our $SERVICE_DIR = $ENV{UBIC_SERVICE_DIR} || '/etc/ubic/services';

sub watchdog_file($) {
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return "$WATCHDOG_DIR/$name";
}

=item B<enable>

Enable service.

Enabled service means that service *should* be running. It will be checked by watchdog and marked as broken if it's enabled but not running.

=cut
sub enable($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $watchdog = Yandex::Persistent->new(watchdog_file($name));
    $watchdog->commit;
}

=item B<is_enabled>

Returns true value if service is enabled, false otherwise.

=cut
sub is_enabled($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return (-e watchdog_file($name)); # watchdog presence means service is running or should be running
}

=item B<disable>

Disable service.

Disabled service means that service is ignored by ubic. It's state will no longer be checked by watchdog, and pings will answer that service is not running, even if it's not true.

=cut
sub disable($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    if ($class->is_enabled($name)) {
        unlink watchdog_file($name) or die "Can't unlink '".watchdog_file($name)."'";
    }
}

=item B<start>

Start service by name.

=cut
sub start($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    $class->enable($name);
    $class->service($name)->start;
}

=item B<stop>

Stop service by name.

=cut
sub stop($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    $class->disable($name);
    $class->service($name)->stop;
}

=item B<restart>

Restart service by name.

=cut
sub restart($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    unless ($class->is_enabled($name)) {
        return 'down';
    }
    $class->service($name)->stop;
    $class->service($name)->start;
}

=item B<status>

Get service status by name.

=cut
sub status($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    $class->service($name)->status;
}

sub service($$) {
    my ($class, $name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $file = "$SERVICE_DIR/$name";
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

sub services($) {
    my ($class) = validate_pos(@_, 1);
    my @services;
    for my $file (glob("$SERVICE_DIR/*")) {
        # TODO - can $SERVICE_DIR contain any subdirs?
        $file = basename($file);
        push @services, $class->service($file);
    }
    return @services;
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

