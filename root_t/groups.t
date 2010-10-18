#!/usr/bin/perl

use strict;
use warnings;

use parent qw(Test::Class);
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use lib '.';

use t::Utils;
use Ubic;

sub setup :Test(setup) {
    rebuild_tfiles();
    Ubic->set_service_dir('root_t/service');
    Ubic->set_data_dir('tfiles');
    xsystem('chmod -R 1777 tfiles');
}

sub file_not_ok {
    my $daemon = shift;
    my $file = "tfiles/$daemon.result";
    ok(-z $file);
}

sub file_ok {
    my $daemon = shift;
    my $file = "tfiles/$daemon.result";
    open my $fh, "<", $file or die "open failed: $!";
    my $line = <$fh>;
    is($line, "abc\n");
}

sub prepare_file($$$$) {
    my ($daemon, $user, $group, $chmod) = @_;
    my $file = "tfiles/$daemon.result";
    my $gid = getgrnam $group;
    my $uid = getpwnam $user;
    open my $fh, ">>", $file or die "open failed: $!";
    close $fh or die "close failed: $!";
    chown $uid, $gid, $file or die "chown failed: $!";
    chmod $chmod, $file or die "chmod failed: $!";
}

sub execute_daemon($) {
    my $name = shift;

    Ubic->start($name);
    sleep 0.1;
    Ubic->stop($name);
}

sub group_ok :Test(1) {
    my $daemon = 'daemongroup-daemon'; # nobody/daemon
    prepare_file($daemon, 'root', 'daemon', 0664);
    execute_daemon($daemon);
    file_ok($daemon);
}

sub group_reset :Test(1) {
    my $daemon = 'daemongroup-daemon'; # nobody/daemon
    prepare_file($daemon, 'root', 'root', 0664);
    eval { execute_daemon($daemon) };
    file_not_ok($daemon); # root group got reset when forking to daemon
}

sub supplementary_group :Test(1) {
    my $daemon = 'daemongroup2-daemon'; # nobody/daemon+root
    prepare_file($daemon, 'root', 'root', 0664);
    execute_daemon($daemon);
    file_ok($daemon);
}

__PACKAGE__->new->runtests;
