package Ubic::Result::Class;

use strict;
use warnings;

=head1 NAME

Ubic::Result::Class - ubic result object

=head1 SYNOPSIS

    use Ubic::Result qw(result);

    my $result = result("already running");
    print $result->status; # running
    print "$result"; # already running

=head1 DESCRIPTION

Many service actions can *do* something and *result* in something.

This class encapsulates both in one handy object.

=head1 STATUSES

Possible statuses:

=over

=item I<running>

=item I<not running>

=item I<broken>

=item I<down>

=back

=head1 ACTIONS

Actions are something that was done which resulted in current status by invoked method.

Possible actions:

=over

=item I<started>

=item I<stopped>

=item I<none>

=item I<reloaded>

=back

=head1 METHODS

=over

=cut

use overload '""' => sub {
    my $self = shift;
    return $self->as_string;
}, 'eq' => sub {
    return ("$_[0]" eq "$_[1]")
}, 'ne' => sub {
    return ("$_[0]" ne "$_[1]")
};

use Params::Validate qw(:all);
use Carp;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw/ type msg /);

=item B<< new({ type => $type, msg => $msg }) >>

Constructor.

=cut
sub new {
    my $class = shift;
    my $self = validate(@_, {
        type => { type => SCALAR, optional => 1 },
        msg => { optional => 1 },
    });
    $self->{type} ||= 'unknown';
    return bless $self => $class;
}

=item B<< status() >>

Get status, see above for possible values.

=cut
sub status {
    my $self = shift;
    croak 'status() is read-only method' if @_;
    if (grep { $_ eq $self->{type} } ('running', 'already running', 'started', 'already started', 'restarted', 'reloaded', 'stopping')) {
        return 'running';
    }
    elsif (grep { $_ eq $self->{type} } ('not running', 'stopped', 'down', 'starting')) {
        return 'not running';
    }
    elsif (grep { $_ eq $self->{type} } ('down')) {
        return 'down';
    }
    else {
        return 'broken';
    }
}

=item B<< action() >>

Get action.

=cut
sub action {
    my $self = shift;
    croak 'action() is read-only method' if @_;
    if (grep { $_ eq $self->{type} } ('started', 'stopped', 'reloaded')) {
        return $self->{type};
    }
    return 'none';
}

=item B<< as_string() >>

Get string representation.

=cut
sub as_string {
    my $self = shift;
    if (defined $self->{msg}) {
        if ($self->{type} eq 'unknown') {
            return "$self->{msg}\n";
        }
        else {
            return "$self->{type} ($self->{msg})";
        }
    }
    else {
        return $self->type;
    }
}

=back

=head1 SEE ALSO

L<Ubic::Result> - service action's result.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;
