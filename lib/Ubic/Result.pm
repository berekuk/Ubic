package Ubic::Result;

use strict;
use warnings;

=head1 NAME

Ubic::Result - common return value for many ubic interfaces

=head1 SYNOPSIS

    use Ubic::Result qw(:all);

    sub start {
        ...
        return result('broken', 'permission denied');
        ...
        return result('running');
        ...
        return 'already running';
    }

=head1 FUNCTIONS

=over

=cut

use Ubic::Result::Class;
use Scalar::Util qw(blessed);
use base qw(Exporter);

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

=head1 SEE ALSO

L<Ubic::Result::Class> - result instance.

=cut

1;

