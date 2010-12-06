use strict;
use warnings;

package Ubic::UserGroupInspection;

use base 'Exporter';
our @EXPORT_OK = qw( effective_group_id real_group_id effective_user_id real_user_id );

BEGIN {
    return if $^O ne 'MSWin32';

    require Win32::pwent;
    push @Win32::pwent::EXPORT_OK, 'endgrent';
    Win32::pwent->import( qw( getpwent endpwent setpwent getpwnam getpwuid getgrent endgrent setgrent getgrnam getgrgid ) );
}

=head2 effective_group_id

Returns OS-independently the effective group id of the current process.

=cut

sub effective_group_id {
    return $) if $^O ne 'MSWin32';
    return _win_current_group_id();
}

=head2 real_group_id

Returns OS-independently the real group id of the current process.

=cut

sub real_group_id {
    return $( if $^O ne 'MSWin32';
    return _win_current_group_id();
}

=head2 _win_current_group_id

Returns the group id of the current process. It is basically just the main group id of the current user.

=cut

sub _win_current_group_id {
    require Win32API::Net;

    my %userInfo;
    Win32API::Net::UserGetInfo( "", getlogin, 4, \%userInfo );
    Win32API::Net::UserGetInfo( "", getlogin, 3, \%userInfo ) if !keys %userInfo;
    die "UserGetInfo() failed: $^E" if !keys %userInfo;

    return "$userInfo{primaryGroupId} $userInfo{primaryGroupId}";
}

=head2 effective_user_id

Returns OS-independently the effective user id of the current process.

=cut

sub effective_user_id {
    return $> if $^O ne 'MSWin32';
    return getpwnam getlogin;
}

=head2 real_user_id

Returns OS-independently the real user id of the current process.

=cut

sub real_user_id {
    return $< if $^O ne 'MSWin32';
    return getpwnam getlogin;
}
