#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Service::PSGI;
use LWP::Simple;

my $port = 5001;
my $service = Ubic::Service::PSGI->new({
    server => 'Standalone',
    server_args => { port => $port },
    app => 't/bin/test.psgi',
    app_name => 'test_psgi',
    status => sub {
        my $result = get("http://localhost:$port") || '';
        if ($result eq 'ok') {
            return 'running';
        }
        else {
            return 'broken';
        }
    },
    ubic_log => 'tfiles/ubic.log',
    stdout => 'tfiles/stdout.log',
    stderr => 'tfiles/stderr.log',
    user => $ENV{LOGNAME},
});

$service->start;
is($service->status, 'running', 'start works');

$service->stop;
is($service->status, 'not running', 'stop works');

$service->start;
is($service->status, 'running', 'another start works');

$service->stop;
is($service->status, 'not running', 'another stop works');

