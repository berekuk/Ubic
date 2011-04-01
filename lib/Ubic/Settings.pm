package Ubic::Settings;

use strict;
use warnings;

# ABSTRACT: ubic settings

=head1 SYNOPSIS

    my $settings = Ubic::Settings->load;

    my $service_dir = $settings->service_dir;
    my $data_dir = $settings->data_dir;
    my $default_user = $settings->default_user;

=head1 DESCRIPTION

This module can be used to get common ubic settings: I<service_dir>, I<data_dir> and I<default_user>.

Note that these settings are global and used by ubic core. Services don't have to use I<data_dir> to store their data, for example; they can use any dir they want.

There are three settings for now:

=over

=item I<service_dir>

Directory with service descriptions. Defaults to I</etc/ubic/service>.

=item I<data_dir>

Dir into which ubic stores all of its data (locks, status files, tmp files). Defaults to I</var/lib/ubic>.

=item I<default_user>

Default user for services which don't specify user themselves. Defaults to I<root>.

=back

These settings are loaded in following order (from the most priority to the least):

=over

=item *

Arguments to C<load()> method.

=item *

Environment variables I<UBIC_SERVICE_DIR> and I<UBIC_DIR> (which affect accordingly I<service_dir> and I<data_dir>);

=item *

Config file at I<~/.ubic.cfg>, if it exists;

=item *

Config file at I</etc/ubic/ubic.cfg>, if it exists and config file in home directory doesn't exist;

=item *

Defaults.

=back

Config files and load arguments don't have to specify all three settings (but note that I</etc/ubic/ubic.cfg> will be ignored if config in home directory exists).

=head1 INTERFACE SUPPORT

This is considered to be a public class. Any changes to its interface will go through a deprecation cycle.

=cut

use Params::Validate qw(:all);

use Ubic::Settings::ConfigFile;

sub load {
    my $class = shift;
    my $options = validate(@_, {
        service_dir => { type => SCALAR, optional => 1 },
        data_dir => { type => SCALAR, optional => 1 },
        default_user => { type => SCALAR, optional => 1 },
    });

    my $config = {};
    if ($ENV{HOME} and -e "$ENV{HOME}/.ubic.cfg") {
        $config = Ubic::Settings::ConfigFile->read("$ENV{HOME}/.ubic.cfg");
    }
    elsif (-e "/etc/ubic/ubic.cfg") {
        $config = Ubic::Settings::ConfigFile->read("/etc/ubic/ubic.cfg");
    }

    return bless {
        service_dir => $ENV{UBIC_SERVICE_DIR} || '/etc/ubic/service',
        data_dir => $ENV{UBIC_DIR} || '/var/lib/ubic',
        default_user => 'root',
        %$config,
        %$options,
    } => $class;
}

sub service_dir {
    my $self = shift;
    validate_pos(@_);
    return $self->{service_dir};
}

sub data_dir {
    my $self = shift;
    validate_pos(@_);
    return $self->{data_dir};
}

sub default_user {
    my $self = shift;
    validate_pos(@_);
    return $self->{default_user};
}

1;
