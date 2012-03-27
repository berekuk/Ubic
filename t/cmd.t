#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 8;

use lib 'lib';

use Ubic::Cmd;

use t::Utils;
rebuild_tfiles();

use Ubic;

local_ubic( service_dirs => [qw( t/service/freaks t/service/common )] );

my $out = '';
open my $fh, '>', \$out;
my $stdout = select $fh;

Ubic::Cmd->start('sleeping-daemon');
select $stdout;
like($out, qr/^\QStarting sleeping-daemon... started (pid \E\d+\)\n$/, 'Ubic::Cmd logged something on start');
is(Ubic->status('sleeping-daemon')->status, 'running', 'Ubic::Cmd really started service');

$out = '';
open $fh, '>', \$out;
select $fh;

Ubic::Cmd->stop('sleeping-daemon');
select $stdout;
is($out, "Stopping sleeping-daemon... stopped\n", 'Ubic::Cmd logged something on stop');
is(Ubic->status('sleeping-daemon'), 'not running', 'Ubic::Cmd really stopped service');

$out = '';
open $fh, '>', \$out;
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


$out = '';
open $fh, '>', \$out;
select $fh;

my $results = Ubic::Cmd->start('broken');
select $stdout;
is($results->exit_code, 1, 'exit code when starting broken service');
like($out, qr{^Starting broken\.\.\. oops, this service can't stop at tfiles/service/broken line \d+\.$}, 'stdout when starting broken service');
