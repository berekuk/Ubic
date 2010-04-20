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
use Ubic::Result qw(result);

use Params::Validate qw(:all);

our $PID_DIR = $ENV{UBIC_DAEMON_PID_DIR} || "/var/lib/ubic/simple-daemon/pid";

=head1 METHODS

=over

=item B<< new($params) >>

Constructor.

Parameters:

=over

=item I<bin>

Daemon binary.

=item I<name>

Service's name. Optional, will usually be set by upper-level multiservice.

=item I<user>

User under which daemon will be started. Optional, default is C<root>.

=item I<stdout>

File into which daemon's stdout will be redirected. Default is C</dev/null>.

=item I<stderr>

File into which daemon's stderr will be redirected. Default is C</dev/null>.

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        bin => { type => SCALAR | ARRAYREF },
        user => { type => SCALAR, optional => 1 },
        name => { type => SCALAR, optional => 1 },
        stdout => { type => SCALAR, optional => 1 },
        stderr => { type => SCALAR, optional => 1 },
    });

    return bless {%$params} => $class;
}

=item B<< pidfile() >>

Get pid filename. It will be concatenated from simple-daemon pid dir and service's name.

=cut
sub pidfile {
    my ($self) = @_;
    my $name = $self->full_name or die "Can't start nameless SimpleDaemon";
    return "$PID_DIR/$name";
}

sub start_impl {
    my ($self) = @_;
    my $start_params = {
        pidfile => $self->pidfile,
        bin => $self->{bin},
        stdout => $self->{stdout} || "/dev/null",
        stderr => $self->{stderr} || "/dev/null",
    };
    if ($self->{user}) {
        $start_params->{user} = $self->{user};
    }
    start_daemon($start_params);
}

sub user {
    my $self = shift;
    return $self->{user} || 'root';
}

sub stop_impl {
    my ($self) = @_;
    stop_daemon($self->pidfile);
}

sub status_impl {
    my ($self) = @_;
    if (check_daemon($self->pidfile)) {
        return result('running');
    }
    else {
        return result('not running');
    }
}

=back

=head1 SEE ALSO

L<Ubic::Daemon> - module to daemonize any binary

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

