package Yandex::Ubic::Service;

use strict;
use warnings;

=head1 NAME

Yandex::Ubic::Service - container specifying one service

=head1 SYNOPSIS

    $service = Yandex::Ubic::Service->new({
        start => sub {
            # implementation-specific
        },
        stop => sub {
            # implementation-specific
        },
        status => sub {
            # implementation-specific
        },
        name => "yandex-ppb-something",
    });
    $service->start;

=head1 DESCRIPTION

Each service should provide safe C<start()>, C<stop()> and C<status()> methods.

=cut

use Yandex::Lockf;
use Yandex::X;
use Yandex::Persistent;

our $WATCHDOG_DIR = "/var/lib/yandex-ubic/watchdogs";
our $LOCK_DIR = "/var/lock/yandex-ubic";

=head1 CONSTRUCTOR

C<< Yandex::Ubic::Service->new($params) >>

Construct service object.

Possible parameters:

=over

=item I<start>

Mandatory sub reference providing service start mechanism.

=item I<stop>

The same for stop.

=item I<status>

Mandatory sub reference checking if service is alive.

It should return one of C<running>, C<not running>, C<broken> values.

This code will be used as safety check against double start and as a watchdog.

=item I<name>

Service's name.

=back

=cut
sub new {
    my ($class, $params) = @_;
    # FIXME - check that params have all required keys
    for my $hook (qw/ start stop status /) {
        die "'$hook' hook not specified" unless exists $params->{$hook};
        die "'$hook' hook should be CODE ref" unless ref($params->{$hook}) eq 'CODE';
    }
    unless (defined $params->{name}) {
        die "name not specified";
    }
    if ($params->{name} !~ /^[\w+\-\.]+$/) {
        die "forbidden name '$params->{name}'";
    }
    my $self = bless {%$params} => $class;
    $self->{watchdog_dir} ||= $WATCHDOG_DIR;
    $self->{lock_dir} ||= $LOCK_DIR;
    return $self;
}

sub name {
    my ($self) = @_;
    return $self->{name};
}

sub lock {
    my $self = shift;
    return lockf("$self->{lock_dir}/$self->{name}");
}

=head1 ACTIONS

=over

=item C<status>

Get status of service.

Possible values: C<running>, C<not running>, C<unknown>, C<broken>.

=cut
sub status {
    my ($self) = @_;
    my $status = $self->{status}->();
    $status ||= 'unknown';
    return $status;
}

=item C<start>

Start service.

Throws exception on failure.

=cut
sub start {
    my ($self) = @_;
    my $lock = $self->lock;
    my $enabled = $self->is_enabled;
    if ($enabled) {
        # already started
        my $status = $self->status;
        if ($status eq 'running') {
            return 'already running';
        } elsif ($status eq 'not running') {
            return $self->do_start;
        } elsif ($status eq 'broken') {
            # checks inside do_start and do_stop guarantee correct status
            $self->do_stop;
            return $self->do_start;
        } else {
            die "Unknown status '$status'";
        }
    } else {
        $self->enable;
        # we shouldn't check status in this case, right? right?
        $self->do_start;
    }
}

=item C<stop>

Stop service.

Return values: C<stopped>, C<not running>.

Throws exception on failure.

=cut
sub stop {
    my ($self) = @_;
    my $lock = $self->lock;
    my $enabled = $self->is_enabled;
    if ($enabled) {
        my $status = $self->status;
        if ($status ne 'not running') {
            $self->do_stop;
        }
        # TODO - check status
        $self->disable; # disabling is a last step - we don't check for running service when watchdog is not installed
        return 'stopped';
    } else {
        return 'not running';
    }
}

=back

=cut

##### internal methods ######
sub watchdog_file {
    my ($self) = @_;
    return "$self->{watchdog_dir}/$self->{name}";
}

sub is_enabled {
    my ($self) = @_;
    return (-e $self->watchdog_file); # watchdog presence means service is running or should be running
}

sub enable {
    my ($self) = @_;
    my $watchdog = Yandex::Persistent->new($self->watchdog_file);
}

sub disable {
    my ($self) = @_;
    if ($self->is_enabled) {
        unlink $self->watchdog_file or die "Can't unlink ".$self->watchdog_file;
    }
}

sub do_start {
    my ($self) = @_;
    $self->{start}->();
    if ($self->status eq 'running') {
        return 'started';
    } else {
        die 'start failed';
    }
}

sub do_stop {
    my ($self) = @_;
    $self->{stop}->();
    if ($self->status eq 'not running') {
        return 'stopped';
    } else {
        die 'stop failed';
    }
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

