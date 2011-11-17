#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More tests => 10;

use t::Utils;

rebuild_tfiles();
local_ubic(service_dirs => ['t/service/multiservice-dir']);

use Ubic;

# we test root_service() method in Ubic.pm here too,
# since it's implemented as Ubic::Multiservice::Dir and it's easier this way.
my $root = Ubic->root_service;

is
    $root->name,
    undef,
    'name of root service is not defined';

is_deeply
    [$root->service_names],
    [qw( foo foo2 foo3 )],
    'list service names on top-level';

ok
    $root->has_simple_service('foo'),
    'foo service is present on top level'
;

ok
    not( $root->has_simple_service('xxx') ),
    'xxx service is not present on top level'
;

my $bar = $root->service('foo.bar');

ok
    $bar->isa('Ubic::Multiservice::Dir'),
    'sub-multiservice is a dir multiservice';

is_deeply
    [$bar->service_names],
    [qw( xxx yyy zzz )],
    'filtering services with various extensions works correctly';

ok
    $bar->has_simple_service('xxx'),
    'xxx service is present in bar'
;

ok
    $bar->has_simple_service('zzz'),
    'zzz service is present in bar'
;

{
    my $warn;
    local $SIG{__WARN__} = sub {
        $warn = shift;
    };

    is
        $bar->service('yyy')->{bin},
        'sleep 100',
        'when in doubt, choose config without extension';

    like $warn, qr/Ignoring duplicate service config/, 'print warning about duplicate configs';
}

