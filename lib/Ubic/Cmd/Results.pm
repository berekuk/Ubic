package Ubic::Cmd::Results;

use strict;
use warnings;

use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

use Params::Validate qw(:all);

# ABSTRACT: console results set

=head1 SYNOPSIS

    use Ubic::Cmd::Results;

    $results = Ubic::Cmd::Results->new;

    $results->print($result);
    $results->print($result, 'bad');
    $results->print($result, 'good');

    $code = $results->finish; # prints final statistics and returns supposed exit code

=head1 DESCRIPTION

This class controls output of service actions.

=head1 METHODS

=over

=item B<< new() >>

Constructor.

=cut
sub new {
    return bless { data => [] } => shift;
}

=item B<< print_bad(@strings) >>

Print given strings in red color if stdout is terminal, and in plain text otherwise.

=cut
sub print_bad {
    my $self = shift;
    if (-t STDOUT) {
        print RED @_;
    }
    else {
        print @_;
    }
}

=item B<< print_good(@strings) >>

Print given strings in green color if stdout is terminal, and in plain text otherwise.

=cut
sub print_good {
    my $self = shift;
    if (-t STDOUT) {
        print GREEN @_;
    }
    else {
        print @_;
    }
}

=item B<< print($result) >>

=item B<< print($result, $type) >>

Print given C<Ubic::Result::Class> object.

C<$type> can be "good" or "bad".

If C<$type> is specified, it is taken into consideration, otherwise result is considered good unless it is "broken".

=cut
sub print($$;$) {
    my $self = shift;
    my ($result, $color) = validate_pos(@_, { isa => 'Ubic::Result::Class' }, { optional => 1, regex => qr/^good|bad$/ });

    $color ||= '';
    if ($result->status eq 'broken' or $color eq 'bad') {
        my $str = "$result";
        chomp $str;
        $self->print_bad("$str\n");
        $self->add($result, 'bad');
    }
    else {
        $self->print_good("$result\n");
        $self->add($result, 'good');
    }

}

=item B<< add($result) >>

Add result without printing.

=cut
sub add {
    my ($self, $result, $type) = @_;
    $type ||= 'good'; # is this too optimistic?
    push @{$self->{data}}, [$result => $type];
}

=item B<< results() >>

Get all results.

=cut
sub results {
    my $self = shift;
    return map { $_->[0] } @{ $self->{data} };
}

=item B<< exit_code() >>

Get exit code appropriate for results.

It can be detected dynamically based on results content, or set explicitly from C<Ubic::Cmd>, depending on command.

=item B<< exit_code($code) >>

Set exit code explicitly.

=cut
sub exit_code {
    my ($self, $new_code) = validate_pos(@_, 1, 0);
    if (defined $new_code) {
        $self->{exit_code} = $new_code;
        return;
    }
    if ($self->{exit_code}) {
        return $self->{exit_code};
    }
    my $data = $self->{data};
    my $bad = grep { $_->[1] eq 'bad' } @$data;
    return ($bad ? 1 : 0);
}


=item B<< finish(\@results) >>

Print error if some of results are bad, and return exit code.

=cut
sub finish($$) {
    my $self = shift;
    my $data = $self->{data};
    my $bad = grep { $_->[1] eq 'bad' } @$data;
    if (@$data > 1) {
        $self->print_bad("Failed: $bad service(s)\n");
    }
    return $self->exit_code;
}

=back

=cut

1;

