#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 7;

use lib 'lib';

use Ubic::Result qw(result);
use Scalar::Util qw(blessed);

is(blessed(result('started')), 'Ubic::Result::Class', 'result function returns result instance');

is(result('started')->status, 'running', 'running->status');
is(result('started')->action, 'started', 'running->action');
is(result('already running')->status, 'running', 'already_running->status');
is(result('already running')->action, 'none', 'already_running->action');

my $result = result('already running');
is("$result", 'already running', 'coercing simple result to string');
$result = result('already running', 'nothing to be done');
is("$result", 'already running (nothing to be done)', 'coercing result with custom message to string');


