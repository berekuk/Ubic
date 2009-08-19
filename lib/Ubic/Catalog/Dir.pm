package Ubic::Catalog::Dir;

use strict;
use warnings;

=head1 NAME

Ubic::Catalog::Dir - service catalog which uses directory with configs to instantiate services

=cut

use base qw(Ubic::Catalog);
use Params::Validate qw(:all);
use Carp;
use Perl6::Slurp;
use File::Basename;
use Scalar::Util qw(blessed);

=head1 METHODS

=over

=item B<< new($dir) >>

Constructor.

=cut
sub new($$) {
    my $class = shift;
    my ($dir) = validate_pos(@_, 1);
    return bless { catalog_dir => $dir } => $class;
}

=item B<< set_catalog_dir($dir) >>

Set catalog dir in runtime.

This class can be mixin to another service, in this case constructor will never be invoked.

=cut
sub set_catalog_dir {
    my $self = shift;
    my $dir = shift;
    $self->{catalog_dir} = $dir;
}


sub has_simple_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return(-e "$self->{catalog_dir}/$name");
}

sub simple_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});

    my $file = "$self->{catalog_dir}/$name";
    if (-e $file) {
        my $content = slurp($file);
        $content = "# line 1 $file\n$content";
        my $service = eval $content;
        if ($@) {
            die "Failed to eval '$file': $@";
        }
        unless (blessed $service) {
            die "$file doesn't contain any service";
        }
        unless ($service->isa('Ubic::Service')) {
            die "$file returned $service instead of Ubic::Service";
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

sub service_names($) {
    my $self = shift;

    my @names;
    for my $file (glob("$self->{catalog_dir}/*")) {
        next unless -f $file;
        # TODO - can $self->{catalog_dir} contain any subdirs?
        $file = basename($file);
        push @names, $file;
    }
    return @names;
}

=back

=head1 SEE ALSO

L<Ubic::Catalog> - base interface of this class.

L<Ubic> - main ubic module uses this for root namespace of services.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

