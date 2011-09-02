package Ubic::Multiservice::Dir;

use strict;
use warnings;

# ABSTRACT: multiservice which uses directory with configs to instantiate services

use parent qw(Ubic::Multiservice);
use Params::Validate qw(:all);
use Carp;
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
        open my $fh, '<', $file or die "Can't open $file: $!";
        my $content = do { local $/; <$fh> };
        close $fh or die "Can't close $file: $!";

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
        my $name = basename($file);

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

        if ($name !~ /^[\w-]+$/) {
            warn "Invalid file $file - only alphanumerics, underscores and hyphens are allowed\n";
            next;
        }

        push @names, $name;
    }
    return @names;
}

=back

=head1 SEE ALSO

L<Ubic::Multiservice> - base interface of this class.

L<Ubic> - main ubic module uses this class as root namespace of services.

=cut

1;

