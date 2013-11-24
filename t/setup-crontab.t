#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use t::Utils;

rebuild_tfiles();

plan skip_all => 'Cannot run t/bin/crontab' if system 't/bin/crontab test';
plan tests => 6;

use Config;
my $perl = $Config{perlpath};
my @crontab_args;

$ENV{ORIGINAL_HOME} = $ENV{HOME};
$ENV{HOME} = 'tfiles';

# removing perlbrew from path, to test default PATH prefix
$ENV{PATH} = join ":", "bin", "t/bin", grep { ! /perlbrew/ } split /:/, $ENV{PATH};

xsystem("$perl ./bin/ubic-admin setup --batch-mode --no-install-services --crontab --local --reconfigure");

ok -e 'tfiles/crontab.log', 'called t/bin/crontab';

open my $LOG, '<', 'tfiles/crontab.log' or die $!;

while(<$LOG>) {
  chomp $_;
  push @crontab_args, $_;
}

is_deeply([ @crontab_args[2, 3] ], ['-l', '---'], 'crontab -l');
is_deeply([ @crontab_args[4, 6] ], ['-', '---'], 'crontab -');

like $crontab_args[5], qr{\* \* \* \* \*}, 'crontab entry will run every minute';
like $crontab_args[5], qr{PATH="bin:\$PATH"}, 'crontab entry prefixed with PATH to ubic-watchdog';

like(
  $crontab_args[5],
  qr{bin/ubic-watchdog ubic\.watchdog >>tfiles/ubic/log/watchdog\.log 2>>tfiles/ubic/log/watchdog\.err\.log},
  'bin/ubic-watchdog ubic.watchdog with logging'
);
