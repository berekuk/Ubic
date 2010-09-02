package Ubic::Service::Common;

use strict;
use warnings;

# ABSTRACT: common way to construct new service by specifying several callbacks

=head1 SYNOPSIS

    $service = Ubic::Service::Common->new({
        start => sub {
            # implementation-specific
        },
        stop => sub {
            # implementation-specific
        },
        status => sub {
            # implementation-specific
        },
        name => "yandex-ppb-something",
        port => 1234,
    });
    $service->start;

=head1 DESCRIPTION

Each service should provide safe C<start()>, C<stop()> and C<status()> methods.

=cut

use Params::Validate qw(:all);

use parent qw(Ubic::Service::Skeleton);

use Carp;

=head1 CONSTRUCTOR

=over

=item B<< Ubic::Service::Common->new($params) >>

Construct service object.

Possible parameters:

=over

=item I<start>

Mandatory sub reference providing service start mechanism.

=item I<stop>

The same for stop.

=item I<status>

Mandatory sub reference checking if service is alive.

It should return one of C<running>, C<not running>, C<broken> values.

This code will be used as safety check against double start and in watchdog checks.

=item I<name>

Service's name.

Optional, will usually be set by upper-level multiservice. Don't set it unless you know what you're doing.

=item I<user>

User under which daemon will be started. Optional, default is C<root>.

=item I<group>

Group under which daemon will be started. Optional, default is all user groups.

Value can be scalar or arrayref.

=item I<port>

Service's port.

=back

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        start       => { type => CODEREF },
        stop        => { type => CODEREF },
        status      => { type => CODEREF },
        name        => { type => SCALAR, regex => qr/^[\w-]+$/, optional => 1 }, # violates Ubic::Service incapsulation...
        port        => { type => SCALAR, regex => qr/^\d+$/, optional => 1 },
        custom_commands => { type => HASHREF, default => {} },
        user        => { type => SCALAR, optional => 1 },
        group       => { type => SCALAR | ARRAYREF, optional => 1 },
        timeout_options => { type => HASHREF, default => {} },
    });
    if ($params->{custom_commands}) {
        for (keys %{$params->{custom_commands}}) {
            ref($params->{custom_commands}{$_}) eq 'CODE' or croak "Callback expected at custom command $_";
        }
    }
    my $self = bless {%$params} => $class;
    return $self;
}

sub port {
    my $self = shift;
    return $self->{port};
}

sub status_impl {
    my $self = shift;
    return $self->{status}->();
}

sub start_impl {
    my $self = shift;
    return $self->{start}->();
}

sub stop_impl {
    my $self = shift;
    return $self->{stop}->();
}

sub timeout_options {
    my $self = shift;
    return $self->{timeout_options};
}

sub custom_commands {
    my $self = shift;
    return keys %{$self->{custom_commands}};
}

sub user {
    my $self = shift;
    return $self->{user} if defined $self->{user};
    return $self->SUPER::user();
}

# copypasted from Ubic::Service::SimpleDaemon... maybe we need moose after all
sub group {
    my $self = shift;
    my $groups = $self->{group};
    return $self->SUPER::group() if not defined $groups;
    return @$groups if ref $groups eq 'ARRAY';
    return $groups;
}

sub do_custom_command {
    my ($self, $command) = @_;
    unless (exists $self->{custom_commands}{$command}) {
        croak "Command '$command' not implemented";
    }
    $self->{custom_commands}{$command}->();
}

1;
