#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More tests => 2;

use t::Utils;

rebuild_tfiles();
local_ubic(service_dirs => ['t/service/loaders']);

use Ubic::ServiceLoader;
use Ubic::Settings;

my $service = Ubic::ServiceLoader->load(Ubic::Settings->service_dir.'/bar.ini');
ok $service->isa('Ubic::Service::SimpleDaemon'), 'service-loader chosen ini loader based on file extension';
is $service->{bin}, 'sleep 200', 'service looks complete';
