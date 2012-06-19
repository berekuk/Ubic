#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Fatal;

if ($^O =~ /MSWin|cygwin|solaris/i) {
    BAIL_OUT("OS unsupported");
}

use lib 'lib';
use File::Find;

my @modules;
find(sub {
    return if $File::Find::name =~ m{Ubic/Run\.pm$};
    if (/\.pm$/) {
        push @modules, $File::Find::name;
    }
}, 'lib');
my @files = glob("bin/*");
plan tests => scalar(@modules) + scalar(@files);

for (@modules) {
    s{^lib/}{};
    s{/}{::}g;
    s{\.pm$}{};
    use_ok($_);
}

for my $file (@files) {
    ok
        not(exception { require $file }),
        "require($file) lives";
}

