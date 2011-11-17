#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;

use lib 'lib';

use Ubic::Multiservice::Simple;
use Ubic::Service::Common;

my $s1 = Ubic::Service::Common->new({ start => sub {}, stop => sub {}, status => sub {} });
my $s2 = Ubic::Service::Common->new({ start => sub {}, stop => sub {}, status => sub {} });

my $level2_s1 = Ubic::Multiservice::Simple->new({
    subservice => $s1,
});

my $level2_s2 = Ubic::Multiservice::Simple->new({
    subservice => $s2,
});

my $level3_s1 = Ubic::Multiservice::Simple->new({
    sub => $level2_s1,
});

my $level3_s2 = Ubic::Multiservice::Simple->new({
    sub => $level2_s2,
});

my $top = Ubic::Multiservice::Simple->new({
    s1 => $level3_s1,
    s2 => $level3_s2,
});

is($top->service('s1.sub.subservice')->full_name, 's1.sub.subservice');
is($top->service('s1')->service('sub.subservice')->full_name, 's1.sub.subservice');
is($top->service('s2')->service('sub.subservice')->parent_name, 's2.sub');
is($top->service('s2.sub')->service('subservice')->parent_name, 's2.sub');

