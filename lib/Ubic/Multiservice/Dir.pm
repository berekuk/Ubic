package Ubic::Multiservice::Dir;

use strict;
use warnings;

# ABSTRACT: multiservice which uses directory with configs to instantiate services

use parent qw(Ubic::Multiservice);
use Params::Validate qw(:all);
use Carp;
use File::Basename;
use Scalar::Util qw(blessed);
use Ubic::ServiceLoader;

=head1 METHODS

=over

=item B<< new($dir) >>

Constructor.

=cut
sub new {
    my $class = shift;
    my ($dir) = validate_pos(@_, 1);
    return bless { service_dir => $dir } => $class;
}

sub has_simple_service {
    my $self = shift;
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    if ($self->_name2file($name)) {
        return 1;
    }
    else {
        return;
    }
}

sub _filter_files {
    my $self = shift;
    my @files = @_;

    my @filtered;
    for my $name (@files) {
        # list of taboo extensions is stolen from logrotate(8)
        if ($name =~ /(
                \.rpmorig   |
                \.rpmsave   |
                ,v          |
                \.swp       |
                \.rpmnew    |
                ~           |
                \.cfsaved   |
                \.rhn-cfg-tmp-.*    |
                \.dpkg-dist |
                \.dpkg-old  |
                \.dpkg-new  |
                \.disabled
            )$/x
        ) {
            next; # skip silently
        }
        push @filtered, $name;
    }
    return @filtered;
}

sub _name2file {
    my $self = shift;
    my ($name) = @_;

    my $base = "$self->{service_dir}/$name";
    my @files = glob "$base.*";
    unshift @files, $base if -e $base;

    @files = $self->_filter_files(@files);

    unless (@files) {
        return;
    }

    if (@files > 1) {
        for my $file (@files[1 .. $#files]) {
            warn "Ignoring duplicate service config '$file', using '$files[0]' instead";
        }
    }
    return shift @files;
}

sub simple_service {
    my $self = shift;
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});

    my $file = $self->_name2file($name);
    unless (defined $file) {
        croak "Service '$name' not found";
    }

    if (-d $file) {
        # directory => multiservice
        my $service = Ubic::Multiservice::Dir->new($file);
        $service->name($name);
        return $service;
    }

    my $service = Ubic::ServiceLoader->load($file);
    $service->name($name);
    return $service;
}

sub service_names {
    my $self = shift;

    my %names;

    my @files = glob("$self->{service_dir}/*");
    @files = $self->_filter_files(@files);
    for my $file (@files) {
        next unless -f $file or -d $file;
        my $name = basename($file);

        my ($service_name, $ext) = Ubic::ServiceLoader->split_service_filename($name);
        unless (defined $service_name) {
            warn "Invalid file $file - only alphanumerics, underscores and hyphens are allowed\n";
            next;
        }

        $names{ $service_name }++;
    }
    return sort keys %names;
}

=back

=head1 SEE ALSO

L<Ubic::Multiservice> - base interface of this class.

L<Ubic> - main ubic module uses this class as root namespace of services.

=cut

1;
