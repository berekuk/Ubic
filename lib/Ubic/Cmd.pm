package Ubic::Cmd;

use strict;
use warnings;

=head1 NAME

Ubic::Cmd - ubic methods with pretty printing.

=head1 SYNOPSIS

    use Ubic::Cmd;
    Ubic::Cmd->start("aaa.bbb");

=head1 SYNOPSIS

When using ubic from simple scripts, you want to print some output about what happened when starting/stopping service.

This package mostly conforms to C<Ubic> module API (i.e. to LSB init-script API).

It also greatly simplifies writing /etc/init.d/ scripts (see synopsis).

=cut

use Params::Validate qw(:all);
use Scalar::Util qw(blessed);

use Ubic;
use Ubic::Result qw(result);

=head1 CONSTRUCTOR

=over

=item B<< new($params) >>

All methods of this class can be invoked as class methods, but you can construct your own instance if neccesary (although constructor doesn't have any options by now, so it is useless).

=cut
sub new {
    my $class = shift;
    my $self = validate(@_, {});
    return bless $self => $class;
}

=back

=cut

our $SINGLETON;
sub _obj {
    my ($param) = validate_pos(@_, 1);
    if (blessed($param)) {
        return $param;
    }
    if ($param eq 'Ubic::Cmd') {
        # method called as a class method => singleton
        $SINGLETON ||= Ubic::Cmd->new();
        return $SINGLETON;
    }
    die "Unknown argument '$param'";
}

=head1 LSB METHODS

All following methods do the same things as methods in C<Ubic>, but they also print messages about their actions.

=over

=item B<< start($name) >>

=cut
sub start {
    my $self = _obj(shift);
    my $name = shift;

    print "Starting $name... ";
    my $result = Ubic->start($name);
    print "$result\n";
    return $result;
}

=item B<< stop($name) >>

=cut
sub stop {
    my $self = _obj(shift);
    my $name = shift;

    print "Stopping $name... ";
    my $result = Ubic->stop($name);
    print "$result\n";
    return $result;
}

=item B<< restart($name) >>

=cut
sub restart {
    my $self = _obj(shift);
    my $name = shift;

    print "Restarting $name... ";
    my $result = Ubic->restart($name);
    print "$result\n";
    return $result;
}

=item B<< try_restart($name) >>

=cut
sub try_restart {
    my $self = _obj(shift);
    my $name = shift;

    if (Ubic->is_enabled($name)) {
        print "Restarting $name... ";
        my $result = Ubic->try_restart($name);
        print "$result\n";
        return $result;
    }
    else {
        print "$name is down";
        return result('down');
    }
}

=item B<< reload($name) >>

=cut
sub reload {
    my $self = _obj(shift);
    my $name = shift;

    if (Ubic->is_enabled($name)) {
        print "Reloading $name... ";
        my $result = Ubic->reload($name);
        print "$result\n";
        return $result;
    }
    else {
        print "$name is down\n";
        return result('down');
    }
}

=item B<< force_reload($name) >>

=cut
sub force_reload {
    my $self = _obj(shift);
    my $name = shift;

    if (Ubic->is_enabled($name)) {
        print "Reloading $name... ";
        my $result = Ubic->force_reload($name);
        print "$result\n";
        return $result;
    }
    else {
        print "$name is down\n";
        return result('down');
    }
}

=back

=head1 OTHER METHODS

=over

=item B<< usage($command) >>

Print command's usage.

WARNING: exits on invocation!

=cut
sub usage {
    my $self = _obj(shift);
    my $command = shift;
    print STDERR "Unknown command '$command'\n";
    exit(2); # or exit(3)? see LSB for details
}

=item B<< print_status($name, $cached_flag) >>

=item B<< print_status($service, $cached_flag) >>

Print status of given service identified by name or by object. If C<$cached_flag> is true, prints status cached in watchdog file.

=cut
sub print_status($$;$) {
    my $self = _obj(shift);
    my ($service, $cached, $indent) = @_;
    $indent ||= 0;

    if (not defined $service) {
        $service = Ubic->root_service;
    }
    elsif (not blessed($service)) {
        $service = Ubic->service($service);
    }
    my $name = $service->full_name;

    if ($service->isa('Ubic::Catalog')) {
        if ($name) {
            print((' ' x $indent).$name.":\n");
            $indent += 4;
        }
        for my $subname ($service->service_names) {
            if ($name) { # not root service
                $subname = $name.".".$subname;
            }
            $self->print_status($subname, $cached, $indent);
        }
        # TODO - print uplevel service's status?
        return;
    }

    my $enabled = Ubic->is_enabled($name);
    unless ($enabled) {
        print((' ' x $indent)."$name\toff\n");
        return result('down');
    }

    my $status = ($cached ? Ubic->cached_status($name) : Ubic->status($name));
    if ($status eq 'running') {
        my $msg;
        $msg .= "\e[32m" if -t STDOUT;
        $msg .= "$name\t$status\n";
        $msg .= "\e[0m" if -t STDOUT;
        print((' ' x $indent).$msg);
    }
    else {
        my $msg;
        $msg .= "\e[31m" if -t STDOUT;
        $msg .= "$name\t$status\n";
        $msg .= "\e[0m" if -t STDOUT;
        print((' ' x $indent).$msg);
    }
    return $status;
}

=item B<< run($params_hashref) >>

Run given command for given service and exit with LSB-compatible exit code.

Parameters:

=over

=item I<name>

Service's name.

=item I<command>

Command to execute.

=item I<args>

Optional arguments (unused by now).

=back

=cut
sub run {
    my $self = _obj(shift);
    my $params = validate(@_, {
        name => { type => SCALAR },
        command => { type => SCALAR, optional => 1 },
        args => { type => ARRAYREF, default => []},
    });
    my $command = $params->{command};
    my @args = @{$params->{args}};
    my $name = $params->{name};

    unless (defined $command) {
        die "No command specified";
    }

    # commands have no arguments (yet)
    $self->usage($command) if @args;

    if ($command eq 'status' or $command eq 'cached-status') {
        my $cached;
        if ($command eq 'status' and $>) {
            print "Not a root, printing cached statuses\n";
            $cached = 1;
        }
        if ($command eq 'cached-status') {
            $cached = 1;
        }
        my $result = $self->print_status($name, $cached);
        if ($result->status eq 'running') {
            exit(0);
        }
        elsif ($result->status eq 'not running' or $result->status eq 'down') {
            exit(3); # see LSB
        }
        else {
            exit(150); # application-reserved code
        }
    }

    # all other commands should be running from root
    if ($>) {
        print STDERR "Permission denied\n";
        exit(4); # see LSB
    }

    my $method = $command;
    $method =~ s/-/_/g;
    unless (grep { $_ eq $method } qw/ start stop restart try_restart reload force_reload /) {
        $self->usage($command);
    }

    unless (Ubic->root_service->has_service($name)) {
        print STDERR "Service '$name' not found\n";
        exit(5);
    }
    eval {
        $self->$method($name);
    }; if ($@) {
        print STDERR "'$name $method' error: $@\n";
        exit(1); # generic error, TODO - more lsb-specific errors?

    }
    exit;
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

