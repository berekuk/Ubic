package Ubic::Multiservice;

use strict;
use warnings;

=head1 NAME

Ubic::Multiservice - interface of multiservice representing several named services

=head1 SYNOPSIS

    $service = $multiservice->service("yandex.yandex-ppb-people-pt.meta-all");
    @services = $multiservice->services();

=head1 DESCRIPTION

Multiservice's interface consists of two fundamental methods: C<service($name)> to get service by it's name, and C<services()> to get list of all services.

Additionally, you can check whether multiservice contains service without instantiating it, using C<has_service($name)> method.

Remember that multiservice is a service too, although it doesn't implement start/stop/status methods. This is because user will usually want to see action's progress, and all output policy is defined in L<Ubic::Cmd> class; interaction protocol between this class and C<Ubic::Cmd> class would be too hard to code.

=head1 METHODS

=over

=cut

use Carp;
use Params::Validate qw(:all);
use base qw(Ubic::Service);

=item B<< service($name) >>

Get service by name.

This class provides common implementation which can delegate searching of subservices to multiservices (don't panic!), so subclasses should implement C<simple_service> instead.

=cut
sub service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+(?:\.[\w-]+)*$} });
    my @parts = split '\\.', $name;

    my $service;
    if (@parts == 1) {
        $service = $self->simple_service($name);
    }
    else {
        # complex service
        my $top_level = $self->simple_service($parts[0]);
        unless ($top_level->isa('Ubic::Multiservice')) {
            croak "top-level service '$parts[0]' is not a multiservice";
        }
        $service = $top_level->service(join '.', @parts[1..$#parts]);
    }
    $service->parent_name($self->name);
    return $service;
}

=item B<< simple_service() >>

This method should be implemented by subclass.

=cut
sub simple_service($$);


=item B<< has_service($name) >>

Check whether service with specified name exists in this multiservice.

Like C<service>, subclasses should usually implement C<has_simple_service> instead.

=cut
sub has_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+(?:\.[\w-]+)*$} });
    my @parts = split '\\.', $name;
    if (@parts == 1) {
        return $self->has_simple_service($name);
    }
    # complex service
    my $top_level = $self->simple_service($parts[0]);
    unless ($top_level->isa('Ubic::Multiservice')) {
        croak "top-level service '$parts[0]' is not a multiservice";
    }
    return $top_level->has_service(join '.', @parts[1..$#parts]);
}

=item B<< has_simple_service($name) >>

This method should be implemented by subclass.

=cut
sub has_simple_service($$);

=item B<< services() >>

Construct all subservices. Because they are top-level, we don't need C<simple_services()>.

By default, it uses C<service_names> to get list of services.
=cut
sub services($) {
    my $self = shift;
    my @services;
    for my $name ($self->service_names) {
        my $service = eval {$self->service($name) };
        if ($@) {
            warn "Can't construct '$name': $@";
            next;
        }
        push @services, $service;
    }
    return @services;
}

=item B<< service_names() >>

Get list with names of all subservices.

Subclasses should usually override this method, C<services> uses it in default implementation.

=cut
sub service_names($);

=item B<< multiop() >>

Get multiop operation mode of object. There are three possible values which this method can return:

=over

=item I<allowed>

C<start>, C<stop>, C<restart> actions for this module start/stop/restart all subservices.

=item I<protected>

I<-f> flag in L<ubic(1)> binary is required to call any action.

=item I<forbidden>

L<ubic(1)> binary will refuse to start/stop/restart this multiservice.

=back

=cut
sub multiop($) {
    return 'protected';
}

=back

=head1 TODO

Implement start/stop/restart methods.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

