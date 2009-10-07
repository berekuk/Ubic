package Ubic::Multiservice::Dir;

use strict;
use warnings;

=head1 NAME

Ubic::Multiservice::Dir - multiservice which uses directory with configs to instantiate services

=cut

use base qw(Ubic::Multiservice);
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
    return bless { service_dir => $dir } => $class;
}

=item B<< set_service_dir($dir) >>

Set service dir in runtime.

This class can be mixin to another service, in this case constructor will never be invoked.

=cut
sub set_service_dir {
    my $self = shift;
    my $dir = shift;
    $self->{service_dir} = $dir; # TODO - check that dir exists?
}


sub has_simple_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});
    return(-e "$self->{service_dir}/$name");
}

my $eval_id = 1;
sub simple_service($$) {
    my $self = shift;
    my ($name) = validate_pos(@_, {type => SCALAR, regex => qr/^[\w.-]+$/});

    my $file = "$self->{service_dir}/$name";
    if (-d $file) {
        # directory => multiservice
        my $service = Ubic::Multiservice::Dir->new($file);
        $service->name($name);
        return $service;
    }
    elsif (-e $file) {
        my $content = slurp($file);
        $content = "# line 1 $file\n$content";
        $content = "package UbicService".($eval_id++).";\n# line 1 $file\n$content";
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
    for my $file (glob("$self->{service_dir}/*")) {
        next unless -f $file or -d $file;
        $file = basename($file);
        next if $file !~ /^[\w-]+$/; # skip files with dots, for example old debian configs like yandex.dpkg-old
        push @names, $file;
    }
    return @names;
}

=back

=head1 SEE ALSO

L<Ubic::Multiservice> - base interface of this class.

L<Ubic> - main ubic module uses this class as root namespace of services.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

