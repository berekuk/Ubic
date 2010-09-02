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
    Ubic->set_service_dir('root_t/service');
    Ubic->set_ubic_dir('tfiles');
    xsystem('chmod -R 777 tfiles');
}

sub test_grants :Tests(6) {
    my $self = shift;
    my $name = $self->{name};
    my $expected_user = $self->{user};
    my $expected_group = $self->{group};
    Ubic->start($name);
    sleep 0.1;
    Ubic->stop($name);

    for my $file ( "tfiles/$name.result", "tfiles/status/$name", "tfiles/lock/$name" ) {
        my @stat = stat($file);
        is($stat[4], scalar(getpwnam($expected_user)), "$file belongs to $expected_user");
        is($stat[5], scalar(getgrnam($expected_group)), "$file group is $expected_group");
    }
}

Test::Class->runtests(
    __PACKAGE__->new({ name => 'daemongroup-daemon', user => 'nobody', group => 'daemon' }),
    __PACKAGE__->new({ name => 'nobody-daemon', user => 'nobody', group => 'nogroup' }),
    __PACKAGE__->new({ name => 'root-daemon', user => 'root', group => 'root' }),
);
