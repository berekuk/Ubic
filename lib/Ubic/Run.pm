package Ubic::Run;

use strict;
use warnings;

=head1 NAME

Ubic::Run - really simple way to write init scripts

=head1 SYNOPSIS

    # /etc/init.d/something:
    use Ubic::Run; # that's all!

=cut

use Ubic::Cmd;

sub import {
    my ($name) = $0 =~ m{^/etc/init\.d/(.+)$} or die "Strange $0";
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
        command => $command,
    });
}


=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

