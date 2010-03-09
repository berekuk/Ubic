package Ubic::Service::PSGI;

use strict;
use warnings;

=head1 NAME

Ubic::Service::PSGI - service wrapper for psgi applications

=head1 SYNOPSIS

    use Ubic::Service::PSGI;
    return Ubic::Service::PSGI->new({
        server => "FCGI",
        server_args => { listen => "/tmp/app.sock",
                         nproc  => 5 },
        app      => "/var/www/app.psgi",
        app_name => 'app',
        status   => sub { ... },
        ubic_log => '/var/log/app/ubic.log',
        stdout   => '/var/log/app/stdout.log',
        stderr   => '/var/log/app/stderr.log',
        user     => "ppb",
    });

=head1 DESCRIPTION

This service is a simplest ubic wrap for psgi applications and uses plackup for running these applications

=cut

use base qw(Ubic::Service::Common);

use Params::Validate qw(:all);
use Time::HiRes qw(usleep);

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);
use Ubic::Result qw(result);
use Ubic::Service::Common;

use Yandex::Config qw(ubic/psgi.cfg);
use vars qw(
    $PSGI_SERVER_ARGS
);

=head1 METHODS

=over

=item C<new($params)>

Parameters (mandatory if not specified otherwise):

=over

=item I<server>

Server name from Plack::Server::* or Plack::Handler::* namespace.
You can pass this param in both variants, for example 'Plack::Handler::FCGI' or just 'FCGI'.

=item I<server_args> (optional)

Hashref with options that will passed to concrete Plack server specified by C<server> param. See concrete server docimentation for possible options.
You can also pass here such options as 'env' to override defaults. In this case you must use long option names ('env' insted of 'E').

=item I<app>

Path to .psgi app.

=item I<app_name>

Name of your application (uses for constructing path for storing pid-file of your app).

=item I<status> (optional)

Coderef to special function, that will check status of your application.

=item I<ubic_log> (optional)

Path to ubic log.

=item I<stdout> (optional)

Path to stdout log of plackup.

=item I<stderr> (optional)

Path to stderr log of plackup.

=item I<user> (optional)

User name. If specified, real and effective user identifiers will be changed before execing any psgi applications.

=back

=back

=head1 OTHERS

/etc/ubic/psgi.cfg - config file with defaults $PSGI_SERVER_ARGS.

=cut

sub new {
    my $class = shift;

    my $params = validate(@_, {
        server      => { type => SCALAR },
        app         => { type => SCALAR },
        app_name    => { type => SCALAR },
        server_args => { type => HASHREF, default => {} },
        user        => { type => SCALAR, optional => 1 },
        status      => { type => CODEREF, optional => 1 },
        ubic_log    => { type => SCALAR, optional => 1 },
        stdout      => { type => SCALAR, optional => 1 },
        stderr      => { type => SCALAR, optional => 1 },
    });

    my $pidfile = "/tmp/" . $params->{app_name} . ".pid";

    my $status_sub = sub {
        my $running = check_daemon($pidfile);
        return 'not running' unless ($running);
        if ($params->{status}) {
            return $params->{status}->();
        } else {
            return 'running';
        }
    };

    my $self = $class->SUPER::new({
        start => sub {
            my %args = %{$PSGI_SERVER_ARGS};
            $args{server} = $params->{server};
            $args{$_} = $params->{server_args}->{$_} for keys %{$params->{server_args}};
            my $cmd = "plackup ";
            foreach my $key (keys %args) {
                $cmd .= "--$key ";
                my $v = $args{$key};
                $cmd .= "$v " if defined($v);
            }
            $cmd .= $params->{app};

            my $daemon_opts = { bin => $cmd, pidfile => $pidfile, term_timeout => 5 };
            for (qw/ubic_log stdout stderr/) {
                $daemon_opts->{$_} = $params->{$_} if $params->{$_};
            }
            start_daemon($daemon_opts);

            my $time = 0;
            my $status;
            for my $trial (1..15) {
                my $sleep = $trial / 10;
                usleep(1_000_000 * $sleep);
                $time += $sleep;
                $status = $status_sub->();
                $status = result($status);
                if ($status->status eq 'running') {
                    return result('started', "started after $time seconds");
                }
                die $status if $status->status eq 'not running';
            }
            return $status;
        },
        stop => sub {
            return stop_daemon($pidfile, { timeout => 7 });
        },
        status => $status_sub,

        user => $params->{user} || 'root',
    });

    return $self;
}

1;

