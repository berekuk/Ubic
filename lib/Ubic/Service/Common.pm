package Ubic::Service::Common;

use strict;
use warnings;

=head1 NAME

Ubic::Service::Common - common way to construct new service by specifying several callbacks

=head1 SYNOPSIS

    $service = Ubic::Service::Common->new({
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

use Params::Validate qw(:all);

use Ubic::Service;
use base qw(Ubic::Service);

use Yandex::Lockf;
use Yandex::X;
use Yandex::Persistent;

our $LOCK_DIR = "/var/lock/ubic"; # FIXME - on some hosts lock dir can be tmpfs!

=head1 CONSTRUCTOR

C<< Ubic::Service::Common->new($params) >>

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
    my $class = shift;
    my $params = validate(@_, {
        start       => { type => CODEREF },
        stop        => { type => CODEREF },
        status      => { type => CODEREF },
        name        => { type => SCALAR, regex => qr/^[\w.-]+$/ },
        lock_dir    => { type => SCALAR, optional => 1},
        port        => { type => SCALAR, regex => qr/^\d+$/, optional => 1},
    });
    my $self = bless {%$params} => $class;
    $self->{lock_dir} ||= $LOCK_DIR;
    return $self;
}

sub port {
    my ($self) = @_;
    return $self->{port};
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

=item C<name>

Returns name specified in constructor.

=cut
sub name {
    my ($self) = @_;
    return $self->{name};
}

=back

=cut

##### internal methods ######

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
    my $status = $self->status;
    if ($status eq 'not running') {
        return 'stopped';
    }
    else {
        die "stop failed, current status: '$status'";
    }
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

