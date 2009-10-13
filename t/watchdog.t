
use strict;
use warnings;

use Test::More tests => 3;

use lib 'lib';

use Yandex::X;
use PPB::Test::TFiles;
use Ubic;

Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');
$ENV{PERL5LIB} = 'lib';

xsystem('fakeroot bin/ubic-watchdog');

Ubic->start('fake-http-service');
Ubic->service('fake-http-service')->stop;

is(scalar(Ubic->service('fake-http-service')->status), 'not running', 'service stopped (i.e. broken)');
like(scalar(xqx('fakeroot bin/ubic-watchdog')), qr/fake-http-service is broken, restarting/, 'watchdog prints logs about restarted service');
is(scalar(Ubic->service('fake-http-service')->status), 'running', 'service is running again');

