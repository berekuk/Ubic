package Ubic::Catalog;

use strict;
use warnings;

=head1 NAME

Ubic::Catalog - interface of catalog representing several named services

=head1 SYNOPSIS

    $service = $catalog->service("yandex/yandex-ppb-people-pt/meta-all");
    @services = $catalog->services();

=head1 DESCRIPTION

Catalog's interface consists of two fundamental methods: C<service($name)> to get service by it's name, and C<services()> to get list of all services.

Additionally, you can check whether catalog contains service without instantiating it, using C<has_service($name)> method.

=head1 METHODS

=over

=cut

use Carp;
use Params::Validate qw(:all);

=item C<service($name)>

Get service by name.

This class provides common implementation which can delegate searching of subservices to multiservices (don't panic!), do subclasses should implement C<simple_service> instead.

=cut
sub service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w.-]+(?:/[\w.-]+)*$} });
    my @parts = split '/', $name;

    my $service;
    if (@parts == 1) {
        $service = $self->simple_service($name);
    }
    else {
        # complex service
        my $top_level = $self->simple_service($parts[0]);
        unless ($top_level->isa('Ubic::Catalog')) {
            croak "top-level service '$parts[0]' is not a multiservice";
        }
        $service = $top_level->service(join '/', @parts[1..$#parts]);
    }
    if ($self->isa('Ubic::Service')) { # multiservice, not most top-level
        $service->name($self->name."/".$service->name); # append upper-level class to name hierarhy
        # beware of services caching! we can accidentally do this twice.
        # would $service->name($name) be simpler solution?
    }
    return $service;
}

=item C<has_service($name)>

Check whether service with specified name exists in this catalog.

Like C<service>, subclasses should usually implement C<has_simple_service> instead.

=cut
sub has_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w.-]+(?:/[\w.-]+)*$} });
    my @parts = split '/', $name;
    if (@parts == 1) {
        return $self->has_simple_service($name);
    }
    # complex service
    my $top_level = $self->simple_service($parts[0]);
    unless ($top_level->isa('Ubic::Catalog')) {
        croak "top-level service '$parts[0]' is not a multiservice";
    }
    return $top_level->has_service(join '/', @parts[1..$#parts]);
}

=item C<services()>

Get all top-level services. Because they are top-level, we don't need C<simple_services()>. Subclasses must override this method.

=cut
sub services($);

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

