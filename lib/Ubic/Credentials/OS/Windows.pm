package Ubic::Credentials::OS::Windows;

use strict;
use warnings;

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

