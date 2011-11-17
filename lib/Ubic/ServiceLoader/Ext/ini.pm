package Ubic::ServiceLoader::Ext::ini;

# ABSTRACT: loader for ini-style configs

=head1 SYNOPSIS

    # in /etc/ubic/service/my.foo file:
    module = Ubic::Service::SimpleDaemon
    [options]
    bin = sleep 100
    stdout = /var/log/my/stdout.log
    stderr = /var/log/my/stderr.log

=cut

use strict;
use warnings;

use parent qw( Ubic::ServiceLoader::Base );

use Config::Tiny;

sub new {
    my $class = shift;
    return bless {} => $class;
}

sub load {
    my $self = shift;
    my ($file) = @_;

    my $config = Config::Tiny->read($file);
    unless ($config) {
        die Config::Tiny->errstr;
    }

    my $root_section = delete $config->{_};
    my $module = delete $root_section->{module} || 'Ubic::Service::SimpleDaemon';
    if (keys %$root_section) {
        die "Unknown option ".join(', ', keys %$root_section)." in file $file";
    }

    my $options = delete $config->{options};
    if (keys %$config) {
        die "Unknown section ".join(', ', keys %$config)." in file $file";
    }

    $module =~ /^[\w:]+$/ or die "Invalid module name '$module'";
    eval "require $module"; # TODO - Class::Load?
    if ($@) {
        die $@;
    }

    my @options = ();
    @options = ($options) if $options; # some modules can have zero options, I guess
    return $module->new(@options);
}

1;
