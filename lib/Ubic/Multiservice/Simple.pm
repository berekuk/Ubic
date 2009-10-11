package Ubic::Multiservice::Simple;

use strict;
use warnings;

=head1 NAME

Ubic::Multiservice::Simple - simplest multiservice, configured in constructor

=head1 SYNOPSIS

use Ubic::Multiservice::Simple;

$ms = Ubic::Multiservice::Simple->new({
    service1 => $s1,
    service2 => $s2,
});

=cut

use Params::Validate qw(:all);
use Scalar::Util qw(blessed);
use base qw(Ubic::Multiservice);

=head1 METHODS

=over

=item C<< new($params) >>

Construct new C<Ubic::Multiservice::Simple> object.

C<$params> must be hashref with service names as keys and services as values.

=cut
sub new {
    my $class = shift;
    my ($params) = validate_pos(@_, {
        type => HASHREF,
        callbacks => {
            'values are services' => sub {
                for (values %{shift()}) {
                    return unless blessed($_) and $_->isa('Ubic::Service')
                }
                return 1;
            },
        }
    });
    return bless { services => $params } => $class;
}

sub has_simple_service($$) {
    my ($self, $name) = @_;
    return exists $self->{services}{$name};
}

sub simple_service($$) {
    my ($self, $name) = @_;
    return $self->{services}{$name};
}

sub service_names($) {
    my $self = shift;
    return keys %{ $self->{services} };
}

sub multiop {
    return 'allowed'; # simple multiservices are usually simple enough to allow multiservice-wide actions by default
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

