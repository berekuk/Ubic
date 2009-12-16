#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;

use lib 'lib';

use Ubic::Cmd;

use PPB::Test::TFiles;
use Yandex::X;

use Ubic;
Ubic->set_ubic_dir('tfiles/ubic');
Ubic->set_service_dir('t/service');

my $out = '';
my $fh = xopen('>', \$out);
my $stdout = select $fh;
Ubic::Cmd->start('sleeping-daemon');
select $stdout;
is($out, "Starting sleeping-daemon... started\n", 'Ubic::Cmd logged something on start');
is(Ubic->status('sleeping-daemon'), 'running', 'Ubic::Cmd really started service');

$out = '';
$fh = xopen('>', \$out);
select $fh;
Ubic::Cmd->stop('sleeping-daemon');
select $stdout;
is($out, "Stopping sleeping-daemon... stopped\n", 'Ubic::Cmd logged something on stop');
is(Ubic->status('sleeping-daemon'), 'not running', 'Ubic::Cmd really stopped service');

$out = '';
$fh = xopen('>', \$out);
select $fh;

eval {
    Ubic::Cmd->do_custom_command('sleeping-common', '2plus2');
};
select $stdout;
if ($@) {
    fail("do_custom_command failed: $@");
}
else {
    pass("do_custom_command is successful");

}
is($out, "Running 2plus2 for sleeping-common... ok\n", 'Ubic::Cmd logged something on custom command');

