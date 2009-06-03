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

Also, other options like I<lock_dir> and I<watchdog_dir> will be propagated to C<Ubic::Service::Common> constructor.

=cut

use Ubic::Service::Common;
use base qw(Ubic::Service::Common);

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

our $PID_DIR = $ENV{PID_DIR} || "/var/lib/yandex-ubic/simple-daemon/pids";

sub new {
    my ($class, $params) = @_;
    my $name = delete $params->{name} or die "name not specified";
    my $bin = delete $params->{bin} or die "bin not specified";

    my $pidfile = "$PID_DIR/$name";

    return $class->SUPER::new({
        %$params,
        name => $name,
        start => sub {
            start_daemon({
                pidfile => $pidfile,
                stdout => "/dev/null",
                stderr => "/dev/null",
                bin => $bin,
            }),
        },
        stop => sub {
            stop_daemon($pidfile);
        },
        status => sub {
            if (check_daemon($pidfile)) {
                return 'running';
            }
            else {
                return 'not running';
            }
        },
    });
}

=head1 SEE ALSO

L<Ubic::Daemon> - module to daemonize any binary

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

