package Ubic::Service::SimpleDaemon;

use strict;
use warnings;

# ABSTRACT: declarative service for daemonizing any binary

=head1 SYNOPSIS

    use Ubic::Service::SimpleDaemon;
    my $service = Ubic::Service::SimpleDaemon->new(
        bin => "sleep 1000",
        stdout => "/var/log/sleep.log",
        stderr => "/var/log/sleep.err.log",
        ubic_log => "/var/log/sleep.ubic.log",
        user => "nobody",
    );

=head1 DESCRIPTION

Use this class to daemonize any binary.

This module uses L<Ubic::Daemon> module for process daemonization. All pidfiles are stored in ubic data dir, with their names based on service names.

=cut

use parent qw(Ubic::Service::Skeleton);

use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);
use Ubic::Result qw(result);
use Ubic::Settings;

use Params::Validate qw(:all);

# Beware - this code will ignore any overrides if you're using custom Ubic->new(...) objects
our $PID_DIR;

sub _pid_dir {
    return $PID_DIR if defined $PID_DIR;
    if ($ENV{UBIC_DAEMON_PID_DIR}) {
        warn "UBIC_DAEMON_PID_DIR env variable is deprecated, use Ubic->set_data_dir or configs instead (see Ubic::Settings for details)";
        $PID_DIR = $ENV{UBIC_DAEMON_PID_DIR};
    }
    else {
        $PID_DIR = Ubic::Settings->data_dir."/simple-daemon/pid";
    }
    return $PID_DIR;
}

=head1 METHODS

=over

=item B<< new($params) >>

Constructor.

Parameters:

=over

=item I<bin>

Daemon binary.

=item I<user>

User under which daemon will be started. Optional, default is C<root>.

=item I<group>

Group under which daemon will be started. Optional, default is all user groups.

Value can be scalar or arrayref.

=item I<stdout>

File into which daemon's stdout will be redirected. Default is C</dev/null>.

=item I<stderr>

File into which daemon's stderr will be redirected. Default is C</dev/null>.

=item I<ubic_log>

Optional filename of ubic log. Log will contain some technical information about running daemon.

=item I<cwd>

Change working directory before starting a daemon. Optional.

=item I<env>

Modify environment before starting a daemon. Optional. Must be a plain hashref if specified.

=item I<reload_signal>

Send given signal to the daemon on C<reload> command.

Can take either integer value or signal name (i.e., I<HUP>).

Note that this signal won't reopen I<stdout>, I<stderr> or I<ubic_log> logs. Sorry.

=item I<name>

Service's name.

Optional, will usually be set by upper-level multiservice. Don't set it unless you know what you're doing.

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        bin => { type => SCALAR | ARRAYREF },
        user => { type => SCALAR, optional => 1 },
        group => { type => SCALAR | ARRAYREF, optional => 1 },
        name => { type => SCALAR, optional => 1 },
        stdout => { type => SCALAR, optional => 1 },
        stderr => { type => SCALAR, optional => 1 },
        ubic_log => { type => SCALAR, optional => 1 },
        cwd => { type => SCALAR, optional => 1 },
        env => { type => HASHREF, optional => 1 },
        reload_signal => { type => SCALAR, optional => 1 },
    });

    return bless {%$params} => $class;
}

=item B<< pidfile() >>

Get pid filename. It will be concatenated from simple-daemon pid dir and service's name.

=cut
sub pidfile {
    my ($self) = @_;
    my $name = $self->full_name or die "Can't start nameless SimpleDaemon";
    return _pid_dir."/$name";
}

sub start_impl {
    my ($self) = @_;

    my $start_params = {
        pidfile => $self->pidfile,
        bin => $self->{bin},
    };
    for (qw/ env cwd stdout stderr ubic_log /) {
        $start_params->{$_} = $self->{$_} if defined $self->{$_};
    }
    start_daemon($start_params);
}

sub user {
    my $self = shift;
    return $self->{user} if defined $self->{user};
    return $self->SUPER::user();
}

sub group {
    my $self = shift;
    my $groups = $self->{group};
    return $self->SUPER::group() if not defined $groups;
    return @$groups if ref $groups eq 'ARRAY';
    return $groups;
}

sub stop_impl {
    my ($self) = @_;
    stop_daemon($self->pidfile);
}

sub status_impl {
    my ($self) = @_;
    if (my $daemon = check_daemon($self->pidfile)) {
        return result('running', "pid ".$daemon->pid);
    }
    else {
        return result('not running');
    }
}

sub reload {
    my $self = shift;
    unless (defined $self->{reload_signal}) {
        return result('unknown', 'not implemented');
    }
    my $daemon = check_daemon($self->pidfile);
    unless ($daemon) {
        return result('not running');
    }

    my $pid = $daemon->pid;
    # TODO - should we send signal to guardian instead?
    # reload doesn't reopen ubic_log/stdout/stderr by now.
    kill $self->{reload_signal} => $pid;

    return result('reloaded', "sent $self->{reload_signal} to $pid");
}

=back

=head1 SEE ALSO

L<Ubic::Daemon> - module to daemonize any binary

=cut

1;
