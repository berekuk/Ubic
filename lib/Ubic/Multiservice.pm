package Ubic::Multiservice;
# ABSTRACT: interface of multiservice representing several named services

use strict;
use warnings;

=head1 SYNOPSIS

    $service = $multiservice->service("multiservice-x.multiservice-y.service-z");
    @services = $multiservice->services();

=head1 DESCRIPTION

Multiservices are objects with simple list/get API which is used to fill ubic service tree.

This is an abstract base class for all multiservices.

Actual multiservice classes should inherit from this class and implement methods from L</"ABSTRACT METHODS"> section.

=head1 ABSTRACT METHODS

These methods have to be overloaded by subclasses:

=over

=item B<< simple_service($name) >>

Should return subservice by its short name (i.e. name without dot separators in it).

=cut
sub simple_service($$);

=item B<< service_names() >>

Should return list with the names of all top-level subservices.

=cut
sub service_names($);

=back

=cut

=head1 METHODS

These methods can be overloaded for a performance boost or some non-trivial tasks, but their default implementation should be adequate in 99% of the cases.

=over

=cut

use Carp;
use Params::Validate qw(:all);
use Try::Tiny;
use parent qw(Ubic::Service);

=item B<< service($name) >>

Get service by name.

This class provides a common implementation which can delegate searching of subservices to multiservices (don't panic!), so subclasses should implement C<simple_service> instead.

All subservices are cached forever.

=cut
sub service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+(?:\.[\w-]+)*$} });
    my @parts = split '\\.', $name;

    if ($self->{service_cache}{$name}) {
        if (my $error = $self->{service_cache}{$name}{error}) {
            die $error;
        }
        else {
            return $self->{service_cache}{$name}{service};
        }
    }

    my $service;
    try {
        if (@parts == 1) {
            $service = $self->simple_service($name);
            unless (defined $service->name) {
                $service->name($name);
            }
            $service->parent_name($self->full_name);
        }
        else {
            # complex service
            my $top_level = $self->simple_service($parts[0]);
            unless ($top_level->isa('Ubic::Multiservice')) {
                croak "top-level service '$parts[0]' is not a multiservice";
            }
            unless (defined $top_level->name) {
                $top_level->name($parts[0]);
            }
            $top_level->parent_name($self->full_name);
            $service = $top_level->service(join '.', @parts[1..$#parts]);
        }
        $self->{service_cache}{$name} = { service => $service };
    }
    catch {
        $self->{service_cache}{$name} = { error => $_ };
        die $_;
    };
    return $service;
}


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
    return undef unless $self->has_service($parts[0]);
    my $top_level = $self->service($parts[0]);
    unless ($top_level->isa('Ubic::Multiservice')) {
        # strange, top-level service is not a multiservice
        return undef;
    }
    return $top_level->has_service(join '.', @parts[1..$#parts]);
}

=item B<< services() >>

Construct all top-level subservices.

By default, it uses C<service_names> to get the list of names.

=cut
sub services($) {
    my $self = shift;
    my @services;
    for my $name ($self->service_names) {
        my $service = eval { $self->service($name) };
        if ($@) {
            warn "Can't construct '$name': $@";
            next;
        }
        push @services, $service;
    }
    return @services;
}

=item B<< has_simple_service($name) >>

Returns true if C<$name> is a subservice of this multiservice.

Default implementation calls C<< $self->service_names >>, so you might want to reimplement it in subclasses for a performance reasons.

=cut
sub has_simple_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, { type => SCALAR, regex => qr{^[\w-]+$} });
    return grep { $_ eq $name } $self->service_names;
}

=item B<< multiop() >>

Get multiop operation mode of a multiservice. There are three possible values which this method can return:

=over

=item I<allowed>

C<start>, C<stop>, C<restart> actions for this module start/stop/restart all subservices.

=item I<protected>

I<-f> flag in L<ubic(1)> binary is required to call any action. This is a default.

=item I<forbidden>

L<ubic(1)> binary will refuse to start/stop/restart this multiservice.

=back

=cut
sub multiop($) {
    return 'protected';
}

=back

=head1 BUGS AND CAVEATS

Although multiservice class is inherited from C<Ubic::Service> class, it doesn't and shouldn't implement start/stop/status methods. This is because user will usually want to see action's progress, and all output policy is defined in L<Ubic::Cmd> class; interaction protocol between this class and C<Ubic::Cmd> class would be too complex.

This may be fixed in future: either C<Ubic::Multiservice> will no longer inherit from C<Ubic::Service>, or start/stop methods will be implemented with renderer object as an argument. Until then, please don't override these methods in subclasses.

C<user>, C<group> and other metadata methods are not used for multiservices too.

Subservices are cached forever; this can cause troubles, but it is necessary to avoid memory leaks in C<Ubic::Ping>.

=head1 SEE ALSO

L<Ubic::Multiservice::Simple> - class for defining simple multiservices.

L<Ubic::Multiservice::Dir> - multiservice which loads service configs from files.

=cut

1;

