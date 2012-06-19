#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;
use Test::Fatal;

use lib 'lib';

use Ubic::Multiservice::Simple;
use Ubic::Service::SimpleDaemon;

my $s1 = Ubic::Service::SimpleDaemon->new({ name => 'sleep', bin => 'sleep 1000' });
my $s2 = Ubic::Service::SimpleDaemon->new({ bin => 'sleep 2000' });

sub generic : Test(8) {
    my $ms = Ubic::Multiservice::Simple->new({
        s1 => $s1,
        s2 => $s2,
    });

    ok(scalar $ms->has_service('s1'), 'has_service returns true for existing service');
    ok(not(scalar $ms->has_service('s3')), 'has_service returns false for non-existing service');

    is_deeply([ sort $ms->services ], [ sort($s1, $s2) ], 'services() return both services');
    is_deeply([ sort $ms->service_names ], [ sort('s1', 's2') ], 'service_names() return both service names');

    $ms->name('named');
    is_deeply([ sort $ms->service_names ], [ sort('s1', 's2') ], "service_names() return both service names even when it's named");

    is(scalar $ms->service('s2')->name, 's2', 'multiservice assigns names to services');
    is(scalar $ms->service('s1')->name, 'sleep', '...unless they are already named');

    my $error = exception {
        Ubic::Multiservice::Simple->new({
            s1 => $s1,
            s2 => 'non-service',
        });
    };
    ok $error, 'new fails when non-service is specified as value';
}

sub nested : Test(4) {
    my $ms = Ubic::Multiservice::Simple->new({
        s1 => $s1,
        m1 => Ubic::Multiservice::Simple->new({
            s2 => $s2,
        }),
    });
    # testing has_service for nested unexistent services
    ok not exception { scalar $ms->has_service('s1.blah') };
    ok not exception { scalar $ms->has_service('s1.blah.blah') };
    ok not exception { scalar $ms->has_service('m1.blah.blah') };
    ok not exception { scalar $ms->has_service('m1.s2.blah') };
}

__PACKAGE__->new->runtests;
