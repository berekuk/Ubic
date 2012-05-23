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

sub new {
    my $class = shift;
    my $params = shift;
    my $self = $class->SUPER::new;
    $self->{$_} = $params->{$_} for keys %$params;
    return $self;
}

sub setup :Test(setup) {
    rebuild_tfiles();
    local_ubic({
        service_dirs => ['root_t/service'],
        default_user => 'root',
    });
    xsystem('chmod -R 777 tfiles');
}

sub test_grants :Tests(8) {
    my $self = shift;
    my $name = $self->{name};
    my $user = $self->{user};
    my $group = $self->{group};
    my $result_user = $self->{result_user} || $user;
    my $result_group = $self->{result_group} || $group;

    Ubic->start($name);
    sleep 0.1;
    Ubic->stop($name);

    my $check_file = sub {
        my ($file, $user, $group) = @_;
        my @stat = stat($file);
        is($stat[4], scalar(getpwnam($user)), "$file belongs to $user");
        is($stat[5], scalar(getgrnam($group)), "$file group is $group");
    };
    $check_file->("tfiles/$name.result", $result_user, $result_group);
    $check_file->("tfiles/$name.ubic.log", $user, $group);
    $check_file->("tfiles/ubic/status/$name", $user, $group);
    $check_file->("tfiles/ubic/lock/$name", $user, $group);
}

Test::Class->runtests(
    __PACKAGE__->new({ name => 'daemongroup-daemon', user => 'nobody', group => 'daemon' }),
    __PACKAGE__->new({ name => 'nobody-daemon', user => 'nobody', group => 'nogroup' }),
    __PACKAGE__->new({ name => 'root-daemon', user => 'root', group => 'root' }),
    __PACKAGE__->new({ name => 'daemon_user', user => 'root', group => 'root', result_user => 'nobody', result_group => 'daemon' }),
);
