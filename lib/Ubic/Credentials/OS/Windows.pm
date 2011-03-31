package Ubic::Credentials::OS::Windows;

use strict;
use warnings;

use parent qw(Ubic::Credentials);

BEGIN {
    return if $^O ne 'MSWin32';

    require Win32::pwent;
    push @Win32::pwent::EXPORT_OK, 'endgrent';
    Win32::pwent->import( qw( getpwent endpwent setpwent getpwnam getpwuid getgrent endgrent setgrent getgrnam getgrgid ) );
}

sub new {
    my $class = shift;
    return bless {} => $class;
}

sub set_effective {}
sub reset_effective {}
sub eq { 1 }
sub set {}

1;

