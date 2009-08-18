package Ubic::Service::SimpleDaemon;

use strict;
use warnings;

=head1 NAME

Ubic::Service::SimpleDaemon - variant of service when your service is simple daemonized binary

=head1 SYNOPSIS

    use Ubic::Service::SimpleDaemon;
    $service = Ubic::Service::SimpleDaemon->new({
        name => "sleep",
        bin => "sleep 1000",
    });
    $service->start;

=head1 DESCRIPTION

Unlike L<Ubic::Service::Common>, this class allows you to specify only name and binary of your service.

=cut

use base qw(Ubic::Service::Skeleton);

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

use Params::Validate qw(:all);

our $PID_DIR = $ENV{UBIC_DAEMON_PID_DIR} || "/var/lib/ubic/simple-daemon/pid";

sub pidfile {
    my ($self) = @_;
    my $name = $self->name or die "Can't start nameless SimpleDaemon";
    return "$PID_DIR/$name";
}

sub new {
    my $class = shift;
    my $params = validate(@_, {
        bin => { type => SCALAR },
        name => { type => SCALAR, optional => 1 },
    });

    return bless {%$params} => $class;
}

sub start_impl {
    my ($self) = @_;
    start_daemon({
        pidfile => $self->pidfile,
        stdout => "/dev/null",
        stderr => "/dev/null",
        bin => $self->{bin},
    }),
}

sub stop_impl {
    my ($self) = @_;
    stop_daemon($self->pidfile);
}

sub status_impl {
    my ($self) = @_;
    if (check_daemon($self->pidfile)) {
        return 'running';
    }
    else {
        return 'not running';
    }
}

=head1 SEE ALSO

L<Ubic::Daemon> - module to daemonize any binary

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

