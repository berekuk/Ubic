package Ubic::Ping::Service;

# ABSTRACT: ubic.ping service

use strict;
use warnings;

use Ubic::Service::Common;
use Ubic::Daemon qw(:all);
use Ubic::Result qw(result);
use Ubic::UA;
use POSIX;
use Time::HiRes qw(sleep);

use Ubic::Settings;

use Config;

=head1 INTERFACE SUPPORT

This is considered to be a non-public class. Its interface is subject to change without notice.

=head1 METHODS

=over

=item B<< new() >>

Constructor.

=cut
sub new {
    # ugly; waiting for druxa's Mopheus to save us all...
    my $port = $ENV{UBIC_SERVICE_PING_PORT} || 12345;
    my $pidfile = Ubic::Settings->data_dir."/ubic-ping.pid";
    my $log = $ENV{UBIC_SERVICE_PING_LOG} || '/dev/null';

    my $perl = $Config{perlpath};

    Ubic::Service::Common->new({
        start => sub {
            my $pid;
            start_daemon({
                bin => qq{$perl -MUbic::Ping -e 'Ubic::Ping->new($port)->run;'},
                name => 'ubic.ping',
                pidfile => $pidfile,
                stdout => $log,
                stderr => $log,
                ubic_log => $log,
            });
        },
        stop => sub {
            stop_daemon($pidfile);
        },
        status => sub {
            my $daemon = check_daemon($pidfile);
            unless ($daemon) {
                return 'not running';
            }
            my $ua = Ubic::UA->new(timeout => 1);
            my $response = $ua->get("http://localhost:$port/ping");
            if ($response->{error}) {
                return result('broken', $response->{error});
            }
            if ($response->{body} =~ /^ok$/ and $response->{code} == 200) {
                return result('running', "pid ".$daemon->pid);
            }
            else {
                return result('broken', $response->{body});
            }
        },
        port => $port,
        timeout_options => { start => { step => 0.1, trials => 3 }},
    });
}

=back

=cut

1;
