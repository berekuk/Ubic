package t::Utils::IgnoreWarn;

use strict;
use warnings;

use t::Utils::IgnoreWarnGuard;

use parent qw(Exporter);
our @EXPORT = qw( ignore_warn );

sub import {
    my $class = shift;

    if ($ENV{IGNORE_WARN}) {
        # parent process has set warn regex
        ignore_warn($ENV{IGNORE_WARN});
    }

    __PACKAGE__->export_to_level(1, @_);
}

sub ignore_warn {
    my $regex = shift;
    return t::Utils::IgnoreWarnGuard->new($regex);
}

1;
