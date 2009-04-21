package Yandex::Ubic::Service::SimpleDaemon;

use strict;
use warnings;

=head1 NAME

Yandex::Ubic::Service::SimpleDaemon - variant of service when your service is simple daemonized binary

=head1 SYNOPSIS

    use Yandex::Ubic::Service::SimpleDaemon;
    $service = Yandex::Ubic::Service::SimpleDaemon->new({
        name => "sleep",
        bin => "sleep 1000",
    });
    $service->start;

=head1 DESCRIPTION

Unlike L<Yandex::Ubic::Service>, this class allows you to specify only name and binary of your service.

Also, other options like I<lock_dir> and I<watchdog_dir> will be propagated to C<Yandex::Ubic::Service> constructor.

=cut

use Yandex::Ubic::Service;
use base qw(Yandex::Ubic::Service);

use Yandex::Ubic::Daemon qw(start_daemon stop_daemon check_daemon);

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

L<Yandex::Ubic::Daemon> - module to daemonize any binary

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

