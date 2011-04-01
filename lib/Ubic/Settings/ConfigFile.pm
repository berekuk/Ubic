package Ubic::Settings::ConfigFile;

use strict;
use warnings;

# ABSTRACT: single ubic config file

=head1 SYNOPSIS

    use Ubic::Service::ConfigFile;

    my $config = Ubic::Service::ConfigFile->read("/etc/ubic/ubic.cfg"); # config is a simple hashref

    Ubic::Service::ConfigFile->write("/etc/ubic/ubic.cfg", { default_user => "root" }); # overwrite old config

=head1 DESCRIPTION

This module can read and write plain ubic config files.

Code outside of C<Ubic>'s core distribution shouldn't use this module. They probably need L<Ubic::Settings> instead.

=head1 INTERFACE SUPPORT

This is considered to be a non-public class. Its interface is subject to change without notice.

=head1 METHODS

=over

=cut

use Params::Validate qw(:all);

=item B<< read($file) >>

Load configuration from file.

=cut
sub read {
    my ($class, $file) = validate_pos(@_, 1, { type => SCALAR });
    unless (-e $file) {
        die "Config file '$file' not found";
    }

    open my $fh, '<', $file or die "Can't open '$file': $!";

    my $config = {};
    while (my $line = <$fh>) {
        chomp $line;
        my ($key, $value) = $line =~ /^(\w+)\s*=\s*(.*)$/;
        $config->{$key} = $value;
    }

    close $fh or die "Can't close '$file': $!";

    return $config;
}

=item B<< write($file, $config_hashref) >>

Write configuration to file.

=cut
sub write {
    my ($class, $file, $config) = validate_pos(@_, 1, { type => SCALAR }, { type => HASHREF });

    my $content = "";

    for my $key (keys %$config) {
        my $value = $config->{$key};
        if ($value =~ /\n/) {
            die "Invalid config line  '$key = $value', values can't contain line breaks";
        }
        $content .= "$key = $value\n";
    }

    # we open file after content is prepared, so that file is not removed if something fails
    # TODO - should we write to tmp file first?
    open my $fh, '>', $file or die "Can't open '$file': $!";
    print {$fh} $content or die "Can't write to '$file': $!; sorry, old config removed!";
    close $fh or die "Can't close '$file': $!";

    return;
}

=back

=cut

1;
