#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};

use Ubic;
use t::Utils;
rebuild_tfiles();

Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');
$ENV{PERL5LIB} = 'lib';

my $ignore_warn = ignore_warn(qr/Can't construct 'broken': failed/);

xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog >tfiles/watchdog.log 2>tfiles/watchdog.err.log");
ok(-z 'tfiles/watchdog.log', 'watchdog is silent when everything is ok');
ok(-z 'tfiles/watchdog.err.log', 'watchdog is silent when everything is ok');

Ubic->start('fake-http-service');
Ubic->service('fake-http-service')->stop;

is(scalar(Ubic->service('fake-http-service')->status), 'not running', 'service stopped (i.e. broken)');

xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog >tfiles/watchdog.log 2>tfiles/watchdog.err.log");
like(slurp('tfiles/watchdog.log'), qr/fake-http-service is broken, restarting/, 'watchdog prints logs about restarted service');
is(slurp('tfiles/watchdog.err.log'), '', "watchdog don't print anything to error log");
is(scalar(Ubic->service('fake-http-service')->status), 'running', 'service is running again');

