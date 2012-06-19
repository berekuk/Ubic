#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More tests => 5;
use Test::Fatal;

use t::Utils;

rebuild_tfiles();
local_ubic(service_dirs => ['t/service/loaders']);

use Ubic::ServiceLoader::Ext::json;
use Ubic::Settings;

my $loader = Ubic::ServiceLoader::Ext::json->new;

{
    my $service = $loader->load(Ubic::Settings->service_dir.'/baz.json');
    ok $service->isa('Ubic::Service::SimpleDaemon'), 'load service using json loader';
    is $service->{bin}, 'sleep 200', 'json loader passes options to constructor';
}

{
    my $service = $loader->load(Ubic::Settings->service_dir.'/j-default-module.json');
    ok $service->isa('Ubic::Service::SimpleDaemon'), 'SimpleDaemon is a default module for json configs';
}

my $error;
$error = exception {
    $loader->load(Ubic::Settings->service_dir.'/jinv.json')
};
like $error, qr/Unknown option/, "attempt to load config with unknown option fails";

$error = exception {
    $loader->load(Ubic::Settings->service_dir.'/jinv2.json')
};
like $error, qr/Failed to parse/, "attempt to load config with syntax error";
