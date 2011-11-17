package Ubic::ServiceLoader;

# ABSTRACT: load service from file

use strict;
use warnings;

=head1 SYNOPSIS

    use Ubic::ServiceLoader;

    $service = Ubic::ServiceLoader->load("/etc/ubic/service/foo.ini");

=head1 DESCRIPTION

This module implements polimorphic loading of service configs.

Specific loader (C<Ubic::ServiceLoader::ini>, C<Ubic::ServiceLoader::bin>, etc.) is chosen based on config file extension.
If config file has no extension then C<Ubic::ServiceLoader::default> will be used.

=head1 INTERFACE SUPPORT

This is considered to be a non-public class. Its interface is subject to change without notice.

=head1 METHODS

=over

=cut

use Params::Validate qw(:all);
use File::Basename;
use Ubic::ServiceLoader::Default;

my %ext2loader;

=item B<ext2loader($ext)>

Get loader object by service extension.

Throws exception is extension is unknown.

=cut
sub ext2loader {
    my $class = shift;
    my ($ext) = validate_pos(@_, { type => SCALAR, regex => qr/^\w+$/ });

    return $ext2loader{$ext} if $ext2loader{$ext};
    require "Ubic/ServiceLoader/Ext/$ext.pm";
    my $loader_class = "Ubic::ServiceLoader::Ext::$ext";
    return $loader_class->new;
}

=item B<split_service_filename($filename)>

Given service config file basename, returns pair C<($service_name, $ext)>.

Returns list with undefs if name is invalid.

=cut
sub split_service_filename {
    my $class = shift;
    my ($filename) = validate_pos(@_, 1);

    my ($service_name, $ext) = $filename =~ /^
        ([\w-]+)
        (?: \.(\w+) )?
    $/x;
    return ($service_name, $ext);
}

=item B<load($filename)>

Load service from config filename.

Throws exception on all errors.

=cut
sub load {
    my $class = shift;
    my ($file) = validate_pos(@_, 1);

    my $filename = basename($file);
    my ($service_name, $ext) = $class->split_service_filename($filename);
    die "Invalid filename '$file'" unless defined $service_name;

    my $loader;
    if ($ext) {
        $loader = $class->ext2loader($ext);
    }
    else {
        $loader = Ubic::ServiceLoader::Default->new;
    }

    my $service = $loader->load($file);
    return $service;
}

=back

=cut

1;
