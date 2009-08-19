#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use lib 'lib';

eval "use Test::Pod::Coverage";
plan skip_all => "Test::Pod::Coverage required for testing POD coverage" if $@;

my $trustparents = { coverage_class => 'Pod::Coverage::CountParents' };

my @modules = all_modules();
plan tests => scalar @modules;
my %modules = map { ($_ => 1) } @modules;

my @bad_modules = qw(
    Ubic::Catalog::Dir
    Ubic::Cmd
);

TODO: {
    local $TODO = 'not all Ubic modules are properly documented still';
    for (@bad_modules) {
        pod_coverage_ok($_, $trustparents);
        delete $modules{$_};
    }
}

for (keys %modules) {
    pod_coverage_ok($_, $trustparents);
}

