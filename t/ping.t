#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 24;

use lib 'lib';

use Test::TCP;
use LWP::UserAgent;
use Ubic;
use Ubic::PortMap;
use Cwd;
use Try::Tiny;

use t::Utils;
rebuild_tfiles();

local_ubic;

my $ignore_warn = ignore_warn(qr/Can't construct 'broken': failed/);

END {
    Ubic->stop('ubic.ping');
}


my $port = empty_port();
$ENV{UBIC_SERVICE_PING_PORT} = $port;
$ENV{UBIC_SERVICE_PING_LOG} = 'tfiles/ubic-ping.log';

try {
    Ubic->start('ubic.ping');
}
catch {
    diag("Error: $_");
    open my $log_fh, '<', 'tfiles/ubic-ping.log' or die "Can't open log: $!";
    my $log = do { local $/ = undef; <$log_fh> };
    $log =~ s/\n/\\n/g;
    BAIL_OUT("Failed to start ubic.ping: $log");
};

Ubic::PortMap::update;

my $another_port = Ubic->service('fake-http-service')->port;

my $ua = LWP::UserAgent->new;

# ping ping (2)
{
    my $response = $ua->get("http://localhost:$port/ping");
    ok($response->is_success, '/ping successful');
    is($response->content, "ok\n", '/ping returns ok');
}

# /status/service/ (9)
{
    my $response = $ua->get("http://localhost:$port/status/service/unknown");
    is($response->code, 404, 'unknown service not found');

    $response = $ua->get("http://localhost:$port/status/service/ubic.ping");
    is($response->code, 200, 'ubic.ping service found');
    is($response->content, "ok\n", 'ubic.ping service is ok');

    $response = $ua->get("http://localhost:$port/status/service/fake-http-service");
    is($response->code, 200, "service fake-http-service found");
    is($response->content, "disabled\n", 'fake-http-service is not running');

    Ubic->start('fake-http-service');
    $response = $ua->get("http://localhost:$port/status/service/fake-http-service");
    is($response->code, 200, "service fake-http-service found");
    is($response->content, "ok\n", 'fake-http-service now is running');

    $response = $ua->get("http://localhost:$port/status/service/fake-http-service2");
    is($response->code, 200, "service fake-http-service2 found");
    is($response->content, "disabled\n", 'fake-http-service is still down');
    Ubic->stop('fake-http-service');
}

# /status/port/ (9)
{
    my $response = $ua->get("http://localhost:$port/status/port/80");
    is($response->code, 404, 'service on 80 port not found');

    $response = $ua->get("http://localhost:$port/status/port/$port");
    is($response->code, 200, "service on $port port found");
    is($response->content, "ok\n", 'ubic.ping service is running');

    $response = $ua->get("http://localhost:$port/status/port/$another_port");
    is($response->code, 200, "service on $another_port port found");
    is($response->content, "disabled\n", 'service is not running');

    Ubic->start('fake-http-service');
    $response = $ua->get("http://localhost:$port/status/port/$another_port");
    is($response->code, 200, "service on $another_port found");
    is($response->content, "ok\n", "service on $another_port now is running");

    Ubic->stop('fake-http-service');
    Ubic->start('fake-http-service2');
    $response = $ua->get("http://localhost:$port/status/port/$another_port");
    is($response->code, 200, "service on $another_port found");
    is($response->content, "ok\n", "service on $another_port is still running - ubic.ping chooses best service by port");

    Ubic->stop('fake-http-service2');
}

# /noc/ (4)
{
    my $response = $ua->get("http://localhost:$port/noc/80");
    is($response->code, 404, 'service on 80 port not found');

    $response = $ua->get("http://localhost:$port/noc/$port");
    is($response->code, 200, "service on $port port found");
    is($response->content, "ok\n", 'ubic.ping service is running');

    $response = $ua->get("http://localhost:$port/noc/$another_port");
    is($response->code, 500, "service on $port port is down");
}
