#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;

use lib 'lib';

use Config;
my $perl = $Config{perlpath};

use Ubic;
use t::Utils;

my $ignore_warn = ignore_warn(qr/Can't construct 'broken': failed/);

# check if we should skip these tests
{
    system('fakeroot true >>/dev/null') and plan skip_all => 'fakeroot is not installed';
}

sub setup :Test(setup) {
    rebuild_tfiles();
    Ubic->set_data_dir('tfiles/ubic');
    Ubic->set_service_dir('t/service');
}

sub silence :Test(2) {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    ok(-z 'tfiles/watchdog.log', 'watchdog is silent when everything is ok');
    ok(-z 'tfiles/watchdog.err.log', 'watchdog is silent when everything is ok');
}

sub reviving :Test(4) {
    Ubic->start('fake-http-service');
    Ubic->service('fake-http-service')->stop;

    is(scalar(Ubic->service('fake-http-service')->status), 'not running', 'service stopped (i.e. broken)');

    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    like(slurp('tfiles/watchdog.log'), qr/fake-http-service is broken, restarting/, 'watchdog prints logs about restarted service');
    is(slurp('tfiles/watchdog.err.log'), '', "watchdog don't print anything to error log");
    is(scalar(Ubic->service('fake-http-service')->status), 'running', 'service is running again');
    Ubic->stop('fake-http-service');
}

sub extended_status :Test(2) {
    Ubic->start('sleeping-daemon');
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    ok(-z 'tfiles/watchdog.log', 'watchdog is silent when everything is ok');
    ok(-z 'tfiles/watchdog.err.log', 'watchdog is silent when everything is ok');
}

sub _services_from_log {
    my $content = slurp('tfiles/watchdog.log');
    my (@services) = $content =~ /Checking (\S+)/g;
    return [ sort @services ];
}

sub verbose :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is(scalar( @{ _services_from_log() }), 12, 'watchdog checks all services by default');
}

sub filter_exact :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v fake-http-service >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is_deeply(_services_from_log(), ['fake-http-service'], 'check one service by its exact name');
}

sub filter_three_exact :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v fake-http-service sleeping-daemon sleeping-common >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is_deeply(_services_from_log(), [qw( fake-http-service sleeping-common sleeping-daemon )], 'check three services by their exact names');
}

sub filter_multi :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v multi >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is_deeply(_services_from_log(), [qw( multi.sleep1 multi.sleep2 )], 'checking multiservice');
}

sub filter_glob :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v '*lti' >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is_deeply(_services_from_log(), [qw( multi.sleep1 multi.sleep2 )], 'checking using glob');
}

sub filter_complex_glob :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v '*ulti*' >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is_deeply(_services_from_log(), [qw( multi-impl.abc multi.sleep1 multi.sleep2 )], 'more complex glob');
}

sub filter_subservice_glob :Test {
    xsystem("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v 'multi.sleep*' >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    is_deeply(_services_from_log(), [qw( multi.sleep1 multi.sleep2 )], 'glob matching subservices');
}

sub filter_validation :Test {
    system("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog -v '[multi]' >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    like(slurp('tfiles/watchdog.err.log'), qr/expected service name or shell-style glob/, 'ubic-watchdog validates arguments');
}

sub check_timeout :Test {
    Ubic->start('slow-service');
    system("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    like(slurp('tfiles/watchdog.log'), qr/slow-service check_timeout exceeded/);
}

sub compile_timeout :Test(3) {
    Ubic->set_service_dir('t/service-slow-compile');
    my $time = time;
    system("fakeroot -- $perl -Mt::Utils bin/ubic-watchdog --compile-timeout=2 >>tfiles/watchdog.log 2>>tfiles/watchdog.err.log");
    ok(time - $time < 4, 'ubic-watchdog compile-timeout happened');
    ok(time - $time >= 2, 'ubic-watchdog compile-timeout happened');
    like(slurp('tfiles/watchdog.err.log'), qr/Couldn't compile Ubic services in 2 seconds/);
}

__PACKAGE__->new->runtests;
