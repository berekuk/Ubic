package Ubic::Catalog;

use strict;
use warnings;

use Yandex::Version '{{DEBIAN_VERSION}}';

=head1 NAME

Ubic::Catalog - catalog of all ubic services

=head1 SYNOPSIS

    Ubic::Catalog->enable("yandex-something");

    Ubic::Catalog->disable("yandex-something");

    $something_enabled = Ubic::Catalog->is_enabled("yandex-something");

=cut

use Params::Validate qw(:all);
use Carp;
use Perl6::Slurp;
use File::Basename;

our $WATCHDOG_DIR = $ENV{UBIC_WATCHDOG_DIR} || "/var/lib/ubic/watchdogs";
our $SERVICE_DIR = $ENV{UBIC_SERVICE_DIR} || '/etc/ubic/services';

sub watchdog_file($) {
    my ($service_name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return "$WATCHDOG_DIR/$service_name";
}

sub enable($$) {
    my ($class, $service_name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $watchdog = Yandex::Persistent->new(watchdog_file($service_name));
}

sub is_enabled($$) {
    my ($class, $service_name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return (-e watchdog_file($service_name)); # watchdog presence means service is running or should be running
}

sub disable($$) {
    my ($class, $service_name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    if ($class->is_enabled($service_name)) {
        unlink watchdog_file($service_name) or die "Can't unlink '".watchdog_file($service_name)."'";
    }
}

sub service($$) {
    my ($class, $service_name) = validate_pos(@_, 1, {type => SCALAR, regex => qr/^[\w.-]+$/});
    my $file = "$SERVICE_DIR/$service_name";
    if (-e $file) {
        my $content = slurp($file);
        $content = "# line 1 $file\n$content";
        my $service = eval $content;
        if ($@) {
            die "Failed to eval '$file': $@";
        }
        return $service;
    }
    else {
        croak "Service '$service_name' not found";
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

