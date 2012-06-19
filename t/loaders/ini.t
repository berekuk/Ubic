#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More tests => 6;
use Test::Fatal;

use t::Utils;

rebuild_tfiles();
local_ubic(service_dirs => ['t/service/loaders']);

use Ubic::ServiceLoader::Ext::ini;
use Ubic::Settings;

my $loader = Ubic::ServiceLoader::Ext::ini->new;

{
    my $service = $loader->load(Ubic::Settings->service_dir.'/bar.ini');
    ok $service->isa('Ubic::Service::SimpleDaemon'), 'load service using ini loader';
    is $service->{bin}, 'sleep 200', 'ini loader passes options to constructor';
}

{
    my $service = $loader->load(Ubic::Settings->service_dir.'/default-module.ini');
    ok $service->isa('Ubic::Service::SimpleDaemon'), 'SimpleDaemon is a default module for ini configs';
}

my $error;
$error = exception {
    $loader->load(Ubic::Settings->service_dir.'/invalid.ini')
};
like $error, qr/Unknown section/, "attempt to load config with unknown section fails";

$error = exception {
    $loader->load(Ubic::Settings->service_dir.'/invalid2.ini')
};
like $error, qr/Unknown option/, "attempt to load config with unknown root-level option";

$error = exception {
    $loader->load(Ubic::Settings->service_dir.'/invalid3.ini')
};
like $error, qr/Syntax error at line 4/, "attempt to load config with syntax error";
