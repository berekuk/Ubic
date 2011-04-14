package Ubic::Credentials::OS::Windows;

use strict;
use warnings;

# ABSTRACT: dummy credentials module

=head1 DESCRIPTION

This module does nothing and always says that credentials are good.

If you are interested in proper Win32 credentials support, look for the patch I<9581a96> in git repo.

You might also want to contact CPAN user I<MITHALDU>, he provided that patch and was generally interested in Win32 port some time ago.

=cut

use parent qw(Ubic::Credentials);

sub new {
    my $class = shift;
    return bless {} => $class;
}

sub set_effective {}
sub reset_effective {}
sub eq { 1 }
sub set {}

1;
