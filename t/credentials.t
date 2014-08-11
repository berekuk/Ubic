#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More;

use Ubic::Credentials;

ok(Ubic::Credentials->new->eq(Ubic::Credentials->new));

done_testing;
