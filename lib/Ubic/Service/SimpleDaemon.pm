package Ubic::Service::SimpleDaemon;

use strict;
use warnings;

# ABSTRACT: service module for daemonizing any binary

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

Use this class to turn any binary into ubic service.

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

Can be a plain string (i.e., C<sleep 10000>), or arrayref with separate arguments (i.e., C<['sleep', '1000']>).

This is the only mandatory parameter, everything else is optional.

=item I<user>

User under which the service will operate.

Default user depends on the configuration chosen at C<ubic-admin setup> stage. See L<Ubic::Settings> for more defails.

=item I<group>

Group under which the service will operate.

Value can be either scalar or arrayref.

Defaults to all groups of service's user.

=item I<stdout>

File into which daemon's stdout will be redirected.  None by default.

=item I<stderr>

File into which daemon's stderr will be redirected. None by default.

=item I<ubic_log>

Optional filename of ubic log. Log will contain some technical information about running daemon.

None by default.

=item I<cwd>

Change working directory before starting a daemon.

=item I<env>

Modify environment before starting a daemon.

Must be a plain hashref if specified.

=item I<ulimit>

Set resource limits before starting a daemon.

Must be a plain hashref with resource names as keys if specified. For example: C<< ulimit => { RLIMIT_NOFILE => 100 } >>. Pass C<-1> as a value to make the resource unlimited.

These limits won't affect anything outside of this service code.

If your service's I<user> is C<root> and I<daemon_user> is something else, you can not just lower limits but raise them as well.

L<BSD::Resource> must be installed to use this feature.

=item I<reload_signal>

Send given signal to the daemon on C<reload> command.

Can take either integer value or signal name (i.e., I<HUP>).

Note that this signal won't reopen I<stdout>, I<stderr> or I<ubic_log> logs. Sorry.

=item I<daemon_user>

=item I<daemon_group>

Change credentials to the given user and group before execing into daemon.

The difference between these options and I<user>/I<group> options is that for I<daemon_*> options, credentials will be set just before before starting the actual daemon. All other service operations will be done using default user. Refer to L<Ubic::Manual::Overview/"Permissions and security"> for the further explanations.

=item I<name>

Service's name.

Name will usually be set by upper-level multiservice. Don't set it unless you know what you're doing.

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        bin => { type => SCALAR | ARRAYREF },
        user => { type => SCALAR, optional => 1 },
        group => { type => SCALAR | ARRAYREF, optional => 1 },
        daemon_user => { type => SCALAR, optional => 1 },
        daemon_group => { type => SCALAR | ARRAYREF, optional => 1 },
        name => { type => SCALAR, optional => 1 },
        stdout => { type => SCALAR, optional => 1 },
        stderr => { type => SCALAR, optional => 1 },
        ubic_log => { type => SCALAR, optional => 1 },
        cwd => { type => SCALAR, optional => 1 },
        env => { type => HASHREF, optional => 1 },
        reload_signal => { type => SCALAR, optional => 1 },
        ulimit => { type => HASHREF, optional => 1 },
    });

    if ($params->{ulimit}) {
        # load BSD::Resource lazily, but fail fast if we're asked for it
        eval "require BSD::Resource";
        if ($@) {
            die "BSD::Resource is not installed";
        }
        if (BSD::Resource->VERSION < 1.29) {
            # 1.29 supports string names for resources
            die "BSD::Resource >= 1.29 required";
        }
    }

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
    if (defined $self->{daemon_user}) {
        $start_params->{credentials} = Ubic::Credentials->new(
            user => $self->{daemon_user},
            group => $self->{daemon_group},
        );
    }
    if (defined $self->{ulimit}) {
        $start_params->{start_hook} = sub {
            for my $name (keys %{$self->{ulimit}}) {
                my $value = $self->{ulimit}{$name};
                my $result = BSD::Resource::setrlimit($name, $value, $value);
                unless ($result) {
                    die "Failed to set $name=$value ulimit";
                }
            }
        };
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

L<Ubic::Daemon> - module for daemonizing any binary.

=cut

1;
