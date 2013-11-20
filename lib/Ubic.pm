package Ubic;

use strict;
use warnings;

# ABSTRACT: polymorphic service manager

=head1 SYNOPSIS

    Configure ubic:
    $ ubic-admin setup

    Write the service config:
    $ cat >/etc/ubic/service/foo.ini
    [options]
    bin = /usr/bin/foo.pl

    Start your service:
    $ ubic start foo

    Enjoy your daemonized, monitored service.

=head1 INTRODUCTION

Ubic is a polymorphic service manager.

Further directions:

if you are looking for a general introduction to Ubic, see L<Ubic::Manual::Intro>;

if you want to use ubic from the command line, see L<ubic>;

if you want to manage ubic services from the perl scripts, read this POD;

if you want to write your own service, see L<Ubic::Service> and other C<Ubic::Service::*> modules.

=head1 DESCRIPTION

This module is a perl frontend to ubic services.

It is a singleton OOP class. All of its methods should be invoked as class methods:

    Ubic->start('foo');
    Ubic->stop('foo');
    my $status = Ubic->status('foo');

=cut

use POSIX qw();
use Carp;
use IO::Handle;
use Storable qw(freeze thaw);
use Try::Tiny;
use Scalar::Util qw(blessed);
use Params::Validate qw(:all);

use Ubic::Result qw(result);
use Ubic::Multiservice::Dir;
use Ubic::AccessGuard;
use Ubic::Credentials;
use Ubic::Persistent;
use Ubic::AtomicFile;
use Ubic::SingletonLock;
use Ubic::Settings;

our $SINGLETON;

my $service_name_re = qr{^[\w-]+(?:\.[\w-]+)*$};
my $validate_service = { type => SCALAR, regex => $service_name_re };

# singleton constructor
sub _obj {
    my ($param) = validate_pos(@_, 1);
    if (blessed($param)) {
        return $param;
    }
    if ($param eq 'Ubic') {
        # method called as a class method => singleton
        $SINGLETON ||= Ubic->new({});
        return $SINGLETON;
    }
    die "Unknown argument '$param'";
}

=head1 CONSTRUCTOR

=over

=item B<< Ubic->new({ ... }) >>

All methods in this package can be invoked as class methods, but sometimes you may need to override some status dirs. In this case you should construct your own C<Ubic> instance.

Note that you can't create several instances in one process and have them work independently. So, this constructor is actually just a weird way to override service_dir and data_dir.

Constructor options (all of them are optional):

=over

=item I<service_dir>

Name of dir with service descriptions (which will be used to construct root C<Ubic::Multiservice::Dir> object).

=item I<data_dir>

Dir into which ubic stores all of its data (locks, status files, tmp files).

=back

=cut
sub new {
    my $class = shift;
    my $options = validate(@_, {
        service_dir =>  { type => SCALAR, optional => 1 },
        data_dir => { type => SCALAR, optional => 1 },
    });

    if (caller ne 'Ubic') {
        warn "Using Ubic->new constructor is discouraged. Just call methods as class methods.";
    }

    for my $key (qw/ service_dir data_dir /) {
        Ubic::Settings->$key($options->{ $key }) if defined $options->{$key};
    }

    Ubic::Settings->check_settings;

    my $self = {};
    $self->{data_dir} = Ubic::Settings->data_dir;
    $self->{service_dir} = Ubic::Settings->service_dir;

    $self->{status_dir} = "$self->{data_dir}/status";
    $self->{lock_dir} = "$self->{data_dir}/lock";
    $self->{tmp_dir} = "$self->{data_dir}/tmp";

    $self->{service_cache} = {};
    return bless $self => $class;
}

=back

=head1 LSB METHODS

See L<LSB documentation|http://refspecs.freestandards.org/LSB_3.1.0/LSB-Core-generic/LSB-Core-generic/iniscrptact.html> for init-script method specifications.

Following methods are trying to conform, except that all dashes in method names are replaced with underscores.

These methods return the result objects, i.e., instances of the C<Ubic::Result::Class> class.

=over

=item B<start($name)>

Start the service.

=cut
sub start($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->do_cmd($name, 'start');
    $self->set_cached_status($name, $result);
    return $result;
}

=item B<stop($name)>

Stop the service.

=cut
sub stop($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    $self->disable($name);

    # FIXME - 'stop' command can fail, in this case daemon will keep running.
    # This is bad.
    # We probably need to implement the same logic as when starting:
    # retry stop attempts until actual status matches desired status.
    my $result = $self->do_cmd($name, 'stop');
    return $result;
}

=item B<restart($name)>

Restart the service; start it if it's not running.

=cut
sub restart($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->do_cmd($name, 'stop');
    $result = $self->do_cmd($name, 'start');

    $self->set_cached_status($name, $result);
    return result('restarted'); # FIXME - should return original status
}

=item B<try_restart($name)>

Restart the service if it is enabled.

=cut
sub try_restart($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return result('down');
    }
    $self->do_cmd($name, 'stop');
    $self->do_cmd($name, 'start');
    return result('restarted');
}

=item B<reload($name)>

Reload the service.

This method will do reloading if the service implements C<reload()>; it will throw an exception otherwise.

=cut
sub reload($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return result('down');
    }

    # if reload isn't implemented, do nothing
    # TODO - would it be better to execute reload as force-reload always? but it would be incompatible with LSB specification...
    my $result = $self->do_cmd($name, 'reload');
    unless ($result->action eq 'reloaded') {
        die $result;
    }
    return $result;
}

=item B<force_reload($name)>

Reload the service if reloading is implemented, otherwise restart it.

Does nothing if service is disabled.

=cut
sub force_reload($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    unless ($self->is_enabled($name)) {
        return result('down');
    }

    my $result = $self->do_cmd($name, 'reload');
    return $result if $result->action eq 'reloaded';

    $self->try_restart($name);
}

=item B<status($name)>

Get the service status.

=cut
sub status($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    return $self->do_cmd($name, 'status');
}

=back

=head1 OTHER METHODS

=over

=item B<enable($name)>

Enable the service.

Enabled service means that service B<should> be running.

Watchdog will periodically check its status, attempt to restart it and mark it as I<broken> if it won't succeed.

=cut
sub enable($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);
    my $guard = $self->access_guard($name);

    my $status_obj = $self->status_obj($name);
    $status_obj->{status} = 'unknown';
    $status_obj->{enabled} = 1;
    $status_obj->commit;
    return result('unknown');
}

=item B<is_enabled($name)>

Check whether the service is enabled.

Returns true or false.

=cut
sub is_enabled($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);

    die "Service '$name' not found" unless $self->root_service->has_service($name);
    unless (-e $self->status_file($name)) {
        return $self->service($name)->auto_start();
    }

    my $status_obj = $self->status_obj_ro($name);
    if ($status_obj->{enabled} or not exists $status_obj->{enabled}) {
        return 1;
    }
    return;
}

=item B<disable($name)>

Disable the service.

Disabled service means that the service is ignored by ubic.

Its state will no longer be checked by the watchdog, and C<ubic status> will report that the service is I<down>.

=cut
sub disable($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);
    my $guard = $self->access_guard($name);

    my $status_obj = $self->status_obj($name);
    delete $status_obj->{status};
    $status_obj->{enabled} = 0;
    $status_obj->commit;
}


=item B<cached_status($name)>

Get cached status of the service.

Unlike other methods, it can be invoked by any user.

=cut
sub cached_status($$) {
    my ($self) = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);

    my $type;
    if (not $self->is_enabled($name)) {
        $type = 'disabled';
    }
    elsif (-e $self->status_file($name)) {
        $type = $self->status_obj_ro($name)->{status};
    } else {
        $type = 'autostarting';
    }
    return Ubic::Result::Class->new({ type => $type, cached => 1 });
}

=item B<do_custom_command($name, $command)>

Execute the custom command C<$command> for the given service.

=cut
sub do_custom_command($$) {
    my ($self) = _obj(shift);
    my ($name, $command) = validate_pos(@_, $validate_service, 1);

    # TODO - do all custom commands require locks?
    # they can be distinguished in future by some custom_commands_ext method which will provide hash { command => properties }, i think...
    my $lock = $self->lock($name);

    # TODO - check custom_command presence by custom_commands() method first?
    $self->do_sub(sub {
        $self->service($name)->do_custom_command($command); # can custom commands require custom arguments?
    });
}

=item B<service($name)>

Get service object by name.

=cut
sub service($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    # this guarantees that : will be unambiguous separator in status filename (what??)
    unless ($self->{service_cache}{$name}) {
        # Service construction is a memory-leaking operation (because of package name randomization in Ubic::Multiservice::Dir),
        # so we need to cache each service which we create.
        $self->{service_cache}{$name} = $self->root_service->service($name);
    }
    return $self->{service_cache}{$name};
}

=item B<< has_service($name) >>

Check whether the service named C<$name> exists.

=cut
sub has_service($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    # TODO - it would be safer to do this check without actual service construction
    # but it would require cron-based script which maintains list of all services
    return $self->root_service->has_service($name);
}

=item B<services()>

Get the list of all services.

=cut
sub services($) {
    my $self = _obj(shift);
    return $self->root_service->services();
}

=item B<service_names()>

Get the list of all service names.

=cut
sub service_names($) {
    my $self = _obj(shift);
    return $self->root_service->service_names();
}

=item B<root_service()>

Get the root multiservice object.

Root service doesn't have a name and returns all top-level services with C<services()> method. You can use it to traverse the whole service tree.

=cut
sub root_service($) {
    my $self = _obj(shift);
    unless (defined $self->{root}) {
        $self->{root} = Ubic::Multiservice::Dir->new($self->{service_dir}, { protected => 1 });
    }
    return $self->{root};
}

=item B<compl_services($line)>

Get the list of autocompletion variants for a given service prefix.

=cut
sub compl_services($$) {
    my $self = _obj(shift);
    my $line = shift;
    my @parts = split /\./, $line;
    if ($line =~ /\.$/) {
        push @parts, '';
    }
    if (@parts == 0) {
        return $self->service_names;
    }
    my $node = $self->root_service;
    my $is_subservice = (@parts > 1);
    while (@parts > 1) {
        unless ($node->isa('Ubic::Multiservice')) {
            return;
        }
        my $part = shift @parts;
        return unless $node->has_service($part); # no such service
        $node = $node->service($part);
    }

    my @variants = $node->service_names;
    return
        map {
            ( $is_subservice ? $node->full_name.".".$_ : $_ )
        }
        grep {
            $_ =~ m{^\Q$parts[0]\E}
        }
        @variants;
}

=item B<set_cached_status($name, $status)>

Write the new status into the service's status file.

=cut
sub set_cached_status($$$) {
    my $self = _obj(shift);
    my ($name, $status) = validate_pos(@_, $validate_service, 1);
    my $guard = $self->access_guard($name);

    if (blessed $status) {
        croak "Wrong status param '$status'" unless $status->isa('Ubic::Result::Class');
        $status = $status->status;
    }
    my $lock = $self->lock($name);

    if (-e $self->status_file($name) and $self->status_obj_ro($name)->{status} eq $status) {
        # optimization - don't update status if nothing changed
        return;
    }

    my $status_obj = $self->status_obj($name);
    $status_obj->{status} = $status;
    $status_obj->commit;
}

=item B<< get_data_dir() >>

Get the data dir.

=cut
sub get_data_dir($) {
    my $self = _obj(shift);
    validate_pos(@_);
    return $self->{data_dir};
}

=item B<< set_data_dir($dir) >>

Set the data dir, creating it if necessary.

Data dir is a directory with service statuses and locks. (See C<Ubic::Settings> for more details on how it's chosen).

This setting will be propagated into subprocesses using environment, so the following code works:

    Ubic->set_data_dir('tfiles/ubic');
    Ubic->set_service_dir('etc/ubic/service');
    system('ubic start some_service');
    system('ubic stop some_service');

=cut
sub set_data_dir($$) {
    my ($arg, $dir) = validate_pos(@_, 1, 1);

    my $md = sub {
        my $new_dir = shift;
        mkdir $new_dir or die "mkdir $new_dir failed: $!" unless -d $new_dir;
    };

    $md->($dir);
    # FIXME - directory list is copy-pasted from Ubic::Admin::Setup
    for my $subdir (qw[
        status simple-daemon simple-daemon/pid lock ubic-daemon tmp watchdog watchdog/lock watchdog/status
    ]) {
        $md->("$dir/$subdir");
    }

    Ubic::Settings->data_dir($dir);
    if ($SINGLETON) {
        $SINGLETON->{lock_dir} = "$dir/lock";
        $SINGLETON->{status_dir} = "$dir/status";
        $SINGLETON->{tmp_dir} = "$dir/tmp";
        $SINGLETON->{data_dir} = $dir;
    }
}

=item B<< set_ubic_dir($dir) >>

Deprecated. This method got renamed to C<set_data_dir()>.

=cut
sub set_ubic_dir($$);
*set_ubic_dir = \&set_data_dir;

=item B<< set_default_user($user) >>

Set default user for all services.

This is a simple proxy for C<< Ubic::Settings->default_user($user) >>.

=cut
sub set_default_user($$) {
    my ($arg, $user) = validate_pos(@_, 1, 1);

    Ubic::Settings->default_user($user);
}

=item B<< get_service_dir() >>

Get the ubic services dir.

=cut
sub get_service_dir($) {
    my $self = _obj(shift);
    validate_pos(@_);
    return $self->{service_dir};
}

=item B<< set_service_dir($dir) >>

Set the ubic services dir.

=cut
sub set_service_dir($$) {
    my ($arg, $dir) = validate_pos(@_, 1, 1);
    Ubic::Settings->service_dir($dir);
    if ($SINGLETON) {
        $SINGLETON->{service_dir} = $dir;
        undef $SINGLETON->{root}; # force lazy regeneration
    }
}

=back

=head1 INTERNAL METHODS

You shouldn't call these from a code which doesn't belong to core Ubic distribution.

These methods can be changed or removed without further notice.

=over

=item B<status_file($name)>

Get the status file name by a service's name.

=cut
sub status_file($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return "$self->{status_dir}/".$name;
}

=item B<status_obj($name)>

Get the status persistent object by a service's name.

It's a bad idea to call this from any other class than C<Ubic>, but if you'll ever want to do this, at least don't forget to create C<Ubic::AccessGuard> first.

=cut
sub status_obj($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return Ubic::Persistent->new($self->status_file($name));
}

=item B<status_obj_ro($name)>

Get the readonly, nonlocked status persistent object (see L<Ubic::Persistent>) by a service's name.

=cut
sub status_obj_ro($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return Ubic::Persistent->load($self->status_file($name));
}

=item B<access_guard($name)>

Get an access guard (L<Ubic::AccessGuard> object) for the given service.

=cut
sub access_guard($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return Ubic::AccessGuard->new(
        Ubic::Credentials->new(service => $self->service($name))
    );
}

=item B<lock($name)>

Acquire lock object for given service.

You can lock one object twice from the same process, but not from different processes.

=cut
sub lock($$) {
    my ($self) = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);

    my $lock = do {
        my $guard = $self->access_guard($name);
        Ubic::SingletonLock->new($self->{lock_dir}."/".$name);
    };
    return $lock;
}

=item B<< do_sub($code) >>

Run any code and wrap any result or exception into a result object.

=cut
sub do_sub($$) {
    my ($self, $code) = @_;
    my $result = try {
        $code->();
    } catch {
        die result($_);
    };
    return result($result);
}

=item B<< do_cmd($name, $cmd) >>

Run C<$cmd> method from the service named C<$name> and wrap any result or exception in a result object.

=cut
sub do_cmd($$$) {
    my ($self, $name, $cmd) = @_;
    $self->do_sub(sub {
        my $service = $self->service($name);

        my $creds = Ubic::Credentials->new( service => $service );

        if ($creds->eq(Ubic::Credentials->new)) {
            # current credentials fit service expectations
            return $service->$cmd();
        }

        # setting just effective uid is not enough, because:
        # - we can accidentally enter tainted mode, and service authors don't expect this
        # - local administrator may want to allow everyone to write their own services, and leaving root as real uid is an obvious security breach
        # (ubic will have to learn to compare service user with service file's owner for such policy to be safe, though - this is not implemented yet)
        $self->forked_call(sub {
            $creds->set();
            return $service->$cmd();
        });
    });
}

=item B<< forked_call($callback) >>

Run a C<$callback> in a subprocess and return its return value.

Interaction happens through a temporary file in C<< $ubic->{tmp_dir} >> dir.

=cut
sub forked_call {
    my ($self, $callback) = @_;
    my $tmp_file = $self->{tmp_dir}."/".time.".$$.".rand(1000000);
    my $child;
    unless ($child = fork) {
        unless (defined $child) {
            die "fork failed";
        }
        my $result;
        try {
            $result = { ok => $callback->() };
        }
        catch {
            $result = { error => $_ };
        };

        try {
            Ubic::AtomicFile::store( freeze($result) => $tmp_file );
            STDOUT->flush;
            STDERR->flush;
            POSIX::_exit(0); # don't allow to lock to be released - this process was forked from unknown environment, don't want to run unknown destructors
        }
        catch {
            # probably tmp_file is not writable
            warn $_;
            POSIX::_exit(1);
        };
    }
    waitpid($child, 0);
    unless (-e $tmp_file) {
        die "temp file $tmp_file not found after fork";
    }
    open my $fh, '<', $tmp_file or die "Can't read $tmp_file: $!";
    my $content = do { local $/; <$fh>; };
    close $fh or die "Can't close $tmp_file: $!";
    unlink $tmp_file;
    my $result = thaw($content);
    if ($result->{error}) {
        die $result->{error};
    }
    else {
        return $result->{ok};
    }
}

=back

=head1 CONTRIBUTORS

Andrei Mishchenko <druxa@yandex-team.ru>

Yury Zavarin <yury.zavarin@gmail.com>

Dmitry Yashin

Christian Walde <walde.christian@googlemail.com>

Ivan Bessarabov <ivan@bessarabov.ru>

Oleg Komarov <komarov@cpan.org>

Andrew Kirkpatrick <ubermonk@gmail.com>

=head1 SEE ALSO

Most Ubic-related links are collected on github wiki: L<http://github.com/berekuk/Ubic/wiki>.

L<Daemon::Control> and L<Proc::Launcher> provide the start/stop/status style mechanisms for init scripts and apachectl-style commands.

L<Server::Control> is an apachectl-style, heavyweight subclassable module for handling network daemons.

L<ControlFreak> - process supervisor, similar to Ubic in its command-line interface.

There are also L<App::Daemon>, L<App::Control> and L<Supervisor>.

=head1 SUPPORT

Our IRC channel is irc://irc.perl.org#ubic.

There's also a mailing list at ubic-perl@googlegroups.com. Send an empty message to ubic-perl+subscribe@googlegroups.com to subscribe.

=cut

1;
