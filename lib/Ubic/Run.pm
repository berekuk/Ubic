package Ubic::Run;

use strict;
use warnings;

# ABSTRACT: really simple way to write init scripts

=head1 SYNOPSIS

    # /etc/init.d/foo:
    use Ubic::Run; # proxy to 'foo' ubic service

    # Or, if you want to rename the service or bind the service containing dots in its name:
    # /etc/init.d/foo-bar:
    use Ubic::Run qw(foo.bar); # proxy to 'foo.bar' ubic service

=head1 DESCRIPTION

This module allows to represent any ubic service as an init script.

It resolves service name automatically by looking at process C<$0>.

Currently, it supports systems where init script is located at C</etc/init.d/> (LSB-compatible systems as specified by L<http://refspecs.freestandards.org/LSB_4.0.0/LSB-Core-generic/LSB-Core-generic/initsrcinstrm.html>, for example, Debian and Ubuntu) and systems where this directory is called C</etc/rc.d/init.d/> (for example, RedHat).

=cut

use Ubic::Cmd;
use Getopt::Long;
use Pod::Usage;

sub import {
    my $class = shift;
    my ($name) = @_;
    unless (defined $name) {
        if ( $0 =~ m{^/etc/init\.d/(.+)$} ) {
            $name = $1;
        }
        elsif ( $0 =~ m{^/etc/rc\d\.d/(?:K|S)\d+(.+)$} ) {
            $name = $1;
        }
        elsif ( $0 =~ m{^/etc/rc\.d/init\.d/(.+)$} ) {
            $name = $1;
        }
        else {
            die "Strange \$0: $0";
        }
    }

    my $force;
    GetOptions(
        'f|force' => \$force,
    ) or die "Unknown option specified";

    my ($command, @args) = @ARGV;
    my @names;
    if (@args) {
        @names = map { "$name.$_" } @args;
    }
    else {
        @names = ($name);
    }
    Ubic::Cmd->run({
        name => \@names,
        ($command ? (command => $command) : ()),
        ($force ? (force => $force) : ()),
    });
}

=head1 BUGS AND CAVEATS

*nix distributions can use different places for init scripts.

If your system doesn't conform to cases listed in description, you'll have to set the service name in import parameters.

Note that you usually don't want to use SysV-style rcX.d runlevel symlinks, because Ubic remembers if service should be running by other means (by storing status files in C</var/lib/ubic/status/>), B<ubic.watchdog> brings all enabled services up in one minute after reboot, and usually it's all you need anyway. See L<Ubic::Manual::FAQ/"How is ubic compatible with SysV-style /etc/rcX.d/ symlinks?"> for more details in this topic.

=head1 SEE ALSO

L<Ubic::Service::InitScriptWrapper> solves the reverse task: represent any init script as ubic service.

=cut

1;
