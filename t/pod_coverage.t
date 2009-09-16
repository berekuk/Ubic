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

for (keys %modules) {
    pod_coverage_ok($_, $trustparents);
}

