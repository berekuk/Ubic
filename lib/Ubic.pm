package Ubic;

use strict;
use warnings;

# ABSTRACT: flexible perl-based service manager

=head1 SYNOPSIS

    Ubic->start("my-service");

    Ubic->stop("my-service");

    $status = Ubic->status("my-service");

=head1 DESCRIPTION

Ubic is a flexible perl-based service manager.

This module is a perl frontend to ubic services.

Further directions:

if you are looking for a general introduction to Ubic, follow this link: L<http://blogs.perl.org/mt/mt-search.fcgi?blog_id=310&tag=tutorial&limit=20>;

if you want to use ubic from command line, see L<ubic>;

if you want to manage ubic services from perl scripts, read this POD;

if you want to write your own service, see L<Ubic::Service> and other C<Ubic::Service::*> modules. Check out L<Ubic::Run> for integration with SysV init script system too.

=cut

use POSIX qw();
use Ubic::Result qw(result);
use Ubic::Multiservice::Dir;
use Ubic::AccessGuard;
use Params::Validate qw(:all);
use Carp;
use IO::Handle;
use Storable qw(freeze thaw);
use Try::Tiny;
use Ubic::Persistent;
use Ubic::SingletonLock;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(uniq);

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

All methods in this package can be invoked as class methods, but sometimes you may need to override some status dirs. In this case you should construct your own instance.

Constructor options (all of them are optional):

=over

=item I<status_dir>

Dir with persistent services' statuses.

=item I<service_dir>

Name of dir with service descriptions (which will be used to construct root Ubic::Multiservice::Dir object)

=item I<lock_dir>

Dir with services' locks.

=back

=cut
sub new {
    my $class = shift;
    my $self = validate(@_, {
        service_dir =>  { type => SCALAR, default => $ENV{UBIC_SERVICE_DIR} || "/etc/ubic/service" },
        data_dir => { type => SCALAR, default => $ENV{UBIC_DIR} || '/var/lib/ubic' },
        status_dir =>  { type => SCALAR, optional => 1 },
        lock_dir =>  { type => SCALAR, optional => 1 },
        tmp_dir =>  { type => SCALAR, optional => 1 },
    });
    if ($self->{status_dir}) {
        warn "'status_dir' option is deprecated; use 'data_dir' instead";
    }
    elsif ($ENV{UBIC_WATCHDOG_DIR}) {
        warn "'UBIC_WATCHDOG_DIR' env variable is deprecated; use 'UBIC_DIR' instead";
        $self->{status_dir} = $ENV{UBIC_WATCHDOG_DIR};
    }
    else {
        $self->{status_dir} = "$self->{data_dir}/status";
    }

    if ($self->{lock_dir}) {
        warn "'lock_dir' option is deprecated; use 'data_dir' instead";
    }
    elsif ($ENV{UBIC_LOCK_DIR}) {
        warn "'UBIC_LOCK_DIR' env variable is deprecated; use 'UBIC_DIR' instead";
        $self->{lock_dir} = $ENV{UBIC_LOCK_DIR};
    }
    else {
        $self->{lock_dir} = "$self->{data_dir}/lock";
    }

    if ($self->{tmp_dir}) {
        warn "'tmp_dir' option is deprecated; use 'data_dir' instead";
    }
    elsif ($ENV{UBIC_TMP_DIR}) {
        warn "'UBIC_TMP_DIR' env variable is deprecated; use 'UBIC_DIR' instead";
        $self->{tmp_dir} = $ENV{UBIC_TMP_DIR};
    }
    else {
        $self->{tmp_dir} = "$self->{data_dir}/tmp";
    }

    $self->{root} = Ubic::Multiservice::Dir->new($self->{service_dir});
    $self->{service_cache} = {};
    return bless $self => $class;
}

=back

=head1 LSB METHODS

See L<http://refspecs.freestandards.org/LSB_3.1.0/LSB-Core-generic/LSB-Core-generic/iniscrptact.html> for init-script method specifications.

Following functions are trying to conform, except that all dashes in method names are replaced with underscores.

Unlike C<Ubic::Service> methods, these methods are guaranteed to return blessed versions of result, i.e. C<Ubic::Result::Class> objects.

=over

=item B<start($name)>

Start service.

=cut
sub start($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->do_cmd($name, 'start');
    $self->set_cached_status($name, $result->status);
    return $result;
}

=item B<stop($name)>

Stop service.

=cut
sub stop($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    $self->disable($name);
    my $result = $self->do_cmd($name, 'stop');
    # we can't save result in status file - it doesn't exist when service is disabled...
    return $result;
}

=item B<restart($name)>

Restart service; start it if it's not running.

=cut
sub restart($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    my $lock = $self->lock($name);

    $self->enable($name);
    my $result = $self->do_cmd($name, 'stop');
    $result = $self->do_cmd($name, 'start');

    $self->set_cached_status($name, $result->status);
    return result('restarted'); # FIXME - should return original status
}

=item B<try_restart($name)>

Restart service if it is enabled.

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

Reloads service if reloading is implemented; throw exception otherwise.

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

Reloads service if reloading is implemented, otherwise restarts it.

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

Get service status.

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

Enable service.

Enabled service means that service *should* be running. It will be checked by status and marked as broken if it's enabled but not running.

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

Returns true value if service is enabled, false otherwise.

=cut
sub is_enabled($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);

    die "Service '$name' not found" unless $self->{root}->has_service($name);
    return unless -e $self->status_file($name);

    my $status_obj = $self->status_obj_ro($name);
    if ($status_obj->{enabled} or not exists $status_obj->{enabled}) {
        return 1;
    }
    return;
}

=item B<disable($name)>

Disable service.

Disabled service means that service is ignored by ubic. It's state will no longer be checked by watchdog, and pings will answer that service is not running, even if it's not true.

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

Get cached status of enabled service.

Unlike other methods, it doesn't require user to be root.

=cut
sub cached_status($$) {
    my ($self) = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);

    unless ($self->is_enabled($name)) {
        return result('disabled');
    }
    return result($self->status_obj_ro($name)->{status});
}

=item B<do_custom_command($name, $command)>

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
        $self->{service_cache}{$name} = $self->{root}->service($name);
    }
    return $self->{service_cache}{$name};
}

=item B<< has_service($name) >>

Check whether service C<$name> exists.

=cut
sub has_service($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    # TODO - it would be safer to do this check without actual service construction
    # but it would require cron-based script which maintains list of all services
    return $self->{root}->has_service($name);
}

=item B<services()>

Get list of all services.

=cut
sub services($) {
    my $self = _obj(shift);
    return $self->{root}->services();
}

=item B<service_names()>

Get list of names of all services.

=cut
sub service_names($) {
    my $self = _obj(shift);
    return $self->{root}->service_names();
}

=item B<root_service()>

Get root service.

Root service doesn't have a name and returns all top-level services with C<services()> method. You can use it to traverse all services' tree.

=cut
sub root_service($) {
    my $self = _obj(shift);
    return $self->{root};
}

=item B<compl_services($line)>

Return list of autocompletion variants for given service prefix.

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

Write new status into service's status file.

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

    my $status_obj = $self->status_obj($name);
    $status_obj->{status} = $status;
    $status_obj->commit;
}

=item B<< get_data_dir() >>

Get data dir.

=cut
sub get_data_dir($) {
    my $self = _obj(shift);
    validate_pos(@_);
    return $self->{data_dir};
}

=item B<< set_data_dir($dir) >>

Create and set data dir.

Data dir is a directory with service statuses and locks. By default, ubic dir is C</var/lib/ubic>, but in tests you may want to change it.

These settings will be propagated into subprocesses using environment, so following code works:

    Ubic->set_data_dir('tfiles/ubic');
    Ubic->set_service_dir('etc/ubic/service');
    system('ubic start some_service');
    system('ubic stop some_service');

=cut
sub set_data_dir($$) {
    my $self = _obj(shift);
    my ($dir) = validate_pos(@_, 1);
    unless (-d $dir) {
        mkdir $dir or die "mkdir $dir failed: $!";
    }

    # TODO - chmod 777, chmod +t?
    # TODO - call this method from postinst too?
    mkdir "$dir/lock" or die "mkdir $dir/lock failed: $!" unless -d "$dir/lock";
    mkdir "$dir/status" or die "mkdir $dir/status failed: $!" unless -d "$dir/status";
    mkdir "$dir/tmp" or die "mkdir $dir/tmp failed: $!" unless -d "$dir/tmp";
    mkdir "$dir/pid" or die "mkdir $dir/pid failed: $!" unless -d "$dir/pid"; # Ubic don't use /pid/, but Ubic::Daemon does

    $self->{lock_dir} = "$dir/lock";
    $self->{status_dir} = "$dir/status";
    $self->{tmp_dir} = "$dir/tmp";
    $self->{data_dir} = $dir;
    $ENV{UBIC_DIR} = $dir;
    $ENV{UBIC_DAEMON_PID_DIR} = "$dir/pid";
}

=item B<< set_ubic_dir($dir) >>

Deprecated. This method got renamed to C<set_data_dir()>.

=cut
sub set_ubic_dir($$);
*set_ubic_dir = \&set_data_dir;

=item B<< get_service_dir() >>

Get ubic services dir.

=cut
sub get_service_dir($) {
    my $self = _obj(shift);
    validate_pos(@_, 0);
    return $self->{service_dir};
}

=item B<< set_service_dir($dir) >>

Set ubic services dir.

=cut
sub set_service_dir($$) {
    my $self = _obj(shift);
    my ($dir) = validate_pos(@_, 1);
    $self->{service_dir} = $dir;
    $ENV{UBIC_SERVICE_DIR} = $dir;
    $self->{root} = Ubic::Multiservice::Dir->new($self->{service_dir}); # FIXME - copy-paste from constructor!
}

=back

=head1 INTERNAL METHODS

You don't need to call these from code which doesn't belong to core Ubic distribution

These methods can be changed or removed without further notice.

=over

=item B<status_file($name)>

Get status file name by service's name.

=cut
sub status_file($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return "$self->{status_dir}/".$name;
}

=item B<status_obj($name)>

Get status persistent object by service's name.

It's a bad idea to call this from any other class than C<Ubic>, but if you'll ever want to do this, at least don't forget to create C<Ubic::AccessGuard> first.

=cut
sub status_obj($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return Ubic::Persistent->new($self->status_file($name));
}

=item B<status_obj_ro($name)>

Get readonly, nonlocked status persistent object by service's name.

=cut
sub status_obj_ro($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return Ubic::Persistent->load($self->status_file($name));
}

=item B<access_guard($name)>

Get access guard (L<Ubic::AccessGuard> object) for given service.

=cut
sub access_guard($$) {
    my $self = _obj(shift);
    my ($name) = validate_pos(@_, $validate_service);
    return Ubic::AccessGuard->new($self->service($name));
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

Run any code and wrap result into C<Ubic::Result::Class> object.

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

sub _groups_equal {
    my ($g1, $g2) = @_;
    my ($main1, @other1) = split / /, $g1;
    my ($main2, @other2) = split / /, $g2;
    return ($main1 == $main2 and join(' ', sort { $a <=> $b } uniq($main1, @other1)) eq join(' ', sort { $a <=> $b } uniq($main2, @other2)));
}

=item B<< do_cmd($name, $cmd) >>

Run C<$cmd> method from service C<$name> and wrap any result or exception into C<Ubic::Result::Class> object.

=cut
sub do_cmd($$$) {
    my ($self, $name, $cmd) = @_;
    $self->do_sub(sub {
        my $service = $self->service($name);

        my $user = $service->user;
        my $service_uid = getpwnam($user);
        unless (defined $service_uid) {
            die "user $user not found";
        }

        my @group = $service->group;

        my @gid;
        for my $group (@group) {
            my $gid = getgrnam($group);
            unless (defined $gid) {
                die "group $group not found";
            }
            push @gid, $gid;
        }
        @gid = (@gid, @gid) if @gid == 1; # otherwise $) = "1 0"; $) = "1" leaves 0 in group list
        my $service_gid = join ' ', @gid;

        if (
            $service_uid == $>
            and $service_uid == $<
            and _groups_equal($service_gid, $))
            and _groups_equal($service_gid, $()
        ) {
            # current euid, ruid, egid, rgid and supplementary groups are all conform to service expectations
            return $service->$cmd();
        }

        # setting just effective uid is not enough, because:
        # - we can accidentally enter tainted mode, and service authors don't expect this
        # - local administrator may want to allow everyone to write service, and leaving root as real uid is an obvious security breach
        # (ubic will have to learn to compare service user with service file's owner for such policy to be save, though - this is not implemented yet)
        $self->forked_call(sub {
            $) = $service_gid;
            unless (_groups_equal($), $service_gid)) {
                die "Failed to set effective gid to $service_gid: $!";
            }
            $( = $gid[0];
            unless (_groups_equal($(, $service_gid)) {
                die "Failed to set real gid to $service_gid: $!";
            }
            $> = $service_uid;
            $< = $service_uid;
            return $service->$cmd();
        });
    });
}

=item B<< forked_call($callback) >>

Run C<$callback> inside fork and return its return value.

Interaction happens through temporary file in C<$ubic->{tmp_dir}> dir.

=cut
sub forked_call {
    my ($self, $callback) = @_;
    my $tmp_file = $self->{tmp_dir}."/".time.".".rand(1000000);
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
            open my $fh, '>', "$tmp_file.tmp" or die "Can't write to '$tmp_file.tmp: $!";
            print {$fh} freeze($result);
            close $fh or die "Can't close $tmp_file.tmp: $!";
            STDOUT->flush;
            STDERR->flush;
            rename "$tmp_file.tmp", $tmp_file;
            POSIX::_exit(0); # don't allow to lock to be released - this process was forked from unknown environment, don't want to run unknown destructors
        }
        catch {
            # probably tmp_file is not writtable
            warn $_;
            POSIX::_exit(1);
        };
    }
    waitpid($child, 0);
    unless (-e $tmp_file) {
        die "temp file not found after fork (probably failed write to $self->{tmp_dir})";
    }
    open my $fh, '<', $tmp_file or die "Can't read $tmp_file: $!";
    my $content = do { local $/; <$fh>; };
    close $fh;
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

=head1 SEE ALSO

Most Ubic-related links are collected on github wiki: L<http://github.com/berekuk/Ubic/wiki>.

=head1 SUPPORT

Our mailing list is ubic-perl@googlegroups.com. Send an empty message to ubic-perl+subscribe@googlegroups.com to subscribe.

These is also an IRC channel: irc://irc.perl.org#ubic.

=cut

1;

