package Yandex::Init;

use strict;
use warnings;

sub run {
    my ($class, $params, @args) = @_;
    die "You should call 'run' as package method" unless $class eq 'Yandex::Init'; # TODO - why?
    die "hashref expected" unless ref($params) eq 'HASH';
    for my $action (/start stop status/) {
        unless (ref($params->{$action}) eq 'CODE') {
            die "Essential action $action implementation is missing";
        }
    }
    unless ($params->{name}) {
        die "name not specified"; # TODO - determine name from $0
    }
    if ($params->{name} !~ /^[\w.-]+$/) {
        die "Strange name $params->{name}";
    }

    my $self = bless {%$params} => $class;

    if (@args != 1) {
        die "Expected action and nothing more";
    }
    my $action = $args[0];
    $self->$action(); # FIXME - check action name? what if action is "run"? :)
}

sub flag_status {
    my ($self) = @_;
    my $watchdog = "/var/lib/yandex-init/watchdogs/$self->{name}";
}

sub start {
    my ($self) = @_;
    if ($self->flag_status()
}


=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

