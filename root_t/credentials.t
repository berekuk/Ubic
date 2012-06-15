#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';

use Test::More;
use parent qw(Test::Class);

use Ubic::Credentials;
use t::Utils;

sub setup :Test(setup) {
    rebuild_tfiles();
    xsystem('chmod -R 777 tfiles');
}

sub current :Tests {
    my $c = Ubic::Credentials->new;

    is($c->user, 'root');

    my @pwnam = getpwnam 'root';
    my $root_group = (getgrgid( (getpwnam 'root')[3] ))[0];
    my ($group) = $c->group;
    is($group, $root_group, "main group is $root_group");
}

sub set :Tests {
    my $file = 'tfiles/blah';
    my $user = 'nobody';
    my $group = 'daemon';

    my $c = Ubic::Credentials->new(user => $user, group => $group);

    my $pid = fork;
    die "fork failed" unless defined $pid;
    unless ($pid) {
        eval {
            $c->set;
            die "Tainted" if ${^TAINT};
            xsystem("touch $file");
        };
        warn "subprocess failed: $@" if $@;
        exit;
    }

    waitpid($pid, 0);
    ok(-f $file);
    my @stat = stat($file);
    is($stat[4], scalar(getpwnam($user)), "$file belongs to $user");
    is($stat[5], scalar(getgrnam($group)), "$file group is $group") unless $^O eq 'darwin';
}

__PACKAGE__->new->runtests;
