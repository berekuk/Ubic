#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 14;

use lib 'lib';

use Yandex::X;
xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

use Ubic::Service::Common;

# common service with methods as callbacks (7)
{
    my $running;
    my $service = Ubic::Service::Common->new({
        start => sub {
            $running++;
        },
        stop => sub {
            $running--;
        },
        status => sub {
            if ($running) {
                return 'running';
            } else {
                return 'not running';
            }
        },
        name => 'some-service',
    });
    is($service->start, 'started', 'start works');
    is($service->status, 'running', 'status after start');

    is($service->stop, 'stopped', 'stop works');
    is($service->status, 'not running', 'status after stop');

    $service->start;
    is($service->start, 'already running', 'double start');

    is($service->stop, 'stopped', 'stop after double start');
    is($service->stop, 'not running', 'double stop');
}

# another service which callbacks returns specific result objects (7)
{
    my $running;
    use Ubic::Result qw(result);
    my $service = Ubic::Service::Common->new({
        start => sub {
            $running++;
        },
        stop => sub {
            $running--;
            return result('stopped', 'hello');
        },
        status => sub {
            if ($running) {
                return result('running', 'hi');
            } else {
                return 'not running';
            }
        },
        name => 'some-service',
    });
    is($service->start, 'started', 'start works');
    is($service->status, 'running (hi)', 'status after start');

    is($service->stop, 'stopped (hello)', 'stop works');
    is($service->status, 'not running', 'status after stop');

    $service->start;
    is($service->start, 'already running', 'double start');

    is($service->stop, 'stopped (hello)', 'stop after double start');
    is($service->stop, 'not running', 'double stop');
}

