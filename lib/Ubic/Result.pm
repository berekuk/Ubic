package Ubic::Result;

use strict;
use warnings;

# ABSTRACT: common return value for many ubic interfaces

=head1 SYNOPSIS

    use Ubic::Result qw(:all);

    sub start {
        ...
        return result('broken', 'permission denied');

        # or:
        return result('running');

        # or:
        return 'already running'; # will be automagically wrapped into result object by Ubic.pm
    }

=head1 FUNCTIONS

=over

=cut

use Ubic::Result::Class;
use Scalar::Util qw(blessed);
use parent qw(Exporter);

our @EXPORT_OK = qw(
    result
);
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

=item C<result($type, $optional_message)>

Construct C<Ubic::Result::Class> instance.

=cut
sub result {
    my ($str, $msg) = @_;
    if (blessed $str and $str->isa('Ubic::Result::Class')) {
        return $str;
    }
    return Ubic::Result::Class->new({ type => "$str", msg => $msg });
}

=back

=head1 POSSIBLE RESULT TYPES

This is a full list of results which can be recognized by L<Ubic::Result::Class>.

Any other result will be interpreted as I<unknown>.

=over

=item I<running>

=item I<not running>

=item I<already running>

=item I<started>

=item I<already started>

=item I<restarted>

=item I<reloaded>

=item I<stopping>

=item I<not running>

=item I<stopped>

=item I<down>

=item I<starting>

=item I<broken>

=back

=head1 SEE ALSO

L<Ubic::Result::Class> - result instance.

=cut

1;

