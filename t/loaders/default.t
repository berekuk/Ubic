#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More tests => 1;

use t::Utils;

rebuild_tfiles();
local_ubic(service_dirs => ['t/service/loaders']);

use Ubic::ServiceLoader::Default;
use Ubic::Settings;

my $service = Ubic::ServiceLoader::Default->new->load(Ubic::Settings->service_dir.'/foo');
ok $service->isa('Ubic::Service::SimpleDaemon'), 'load service using default loader';

