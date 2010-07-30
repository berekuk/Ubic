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
use List::MoreUtils qw(any);
use List::Util qw(max);
use Try::Tiny;
use Ubic;
use Ubic::Result qw(result);
use Ubic::Cmd::Results;

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

=cut

sub _any_method {
    my $self = shift;
    my $params = validate(@_, {
        service => 1,
        results => 0,
        action => 1, # Starting/Stopping/...
        method => 1,
        enabled_only => 0,
    });
    my ($service, $results, $action, $method, $enabled_only)  = @$params{qw/ service results action method enabled_only /};
    $results ||= Ubic::Cmd::Results->new;

    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;
        if ($enabled_only and not Ubic->is_enabled($name)) {
            print "$name is down\n";
            $results->add(result('down'));
            return;
        }
        print "$action $name... ";
        my $result = eval { Ubic->$method($name) };
        $result ||= result($@);
        $results->print($result, $@ ? 'bad' : ());
    });
    return $results;
}

=item B<< start($service) >>

=cut
sub start {
    my $self = _obj(shift);
    return $self->_any_method({
        service => shift,
        results => shift,
        action => 'Starting',
        method => 'start',
    });
}


=item B<< stop($service) >>

=cut
sub stop {
    my $self = _obj(shift);
    return $self->_any_method({
        service => shift,
        results => shift,
        action => 'Stopping',
        method => 'stop',
    });
}

=item B<< restart($service) >>

=cut
sub restart {
    my $self = _obj(shift);
    return $self->_any_method({
        service => shift,
        results => shift,
        action => 'Restarting',
        method => 'restart',
    });
}

=item B<< try_restart($service) >>

=cut
sub try_restart {
    my $self = _obj(shift);
    return $self->_any_method({
        service => shift,
        results => shift,
        action => 'Restarting',
        method => 'try_restart',
        enabled_only => 1,
    });
}

=item B<< reload($service) >>

=cut
sub reload {
    my $self = _obj(shift);
    return $self->_any_method({
        service => shift,
        results => shift,
        action => 'Reloading',
        method => 'reload',
        enabled_only => 1,
    });
}

=item B<< force_reload($name) >>

=cut
sub force_reload {
    my $self = _obj(shift);
    return $self->_any_method({
        service => shift,
        results => shift,
        action => 'Reloading',
        method => 'force_reload',
        enabled_only => 1,
    });
}

=back

=head1 OTHER METHODS

=over

=item B<< do_custom_command($service, $command) >>

Do non-LSB command.

=cut
sub do_custom_command {
    my $self = _obj(shift);
    my $service = shift;
    my $command = shift;
    my $results = shift || Ubic::Cmd::Results->new;

    my $count = 0;
    my $error = 0;
    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;

        # Imagine we have multiservice X with subservices X.A, X.B and X.C.
        # X may want to support custom command CC by implementing it in X.A and X.B but not in X.C.
        # In this case X.A->CC and X.B->CC will be called, and X.C will be skipped.
        if (grep { $_ eq $command } $service->custom_commands) {
            print "Running $command for $name... ";
            try {
                Ubic->do_custom_command($name, $command);
                $results->print(result('unknown', 'ok'));
            } catch {
                $results->print(result('unknown', "failed: $_"), 'bad');
            };
            $count++;
        }
    });
    unless ($count) {
        # But if none of X subservices support our custom command, something is obviously wrong.
        if ($service->isa('Ubic::Multiservice')) {
            die "None of ".$service->full_name." subservices support $command";
        }
        else {
            # it is unlikely that this error will happen, because we already checked that $service supports $command
            die "$command unsupported";
        }
    }

    # TODO - what if X want to implement custom command itself?
    # should custom commands have different types, "try to call me in each subservice" and "call me for multiservice itself"?

    return;
}

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


=item B<< traverse($name, $callback) >>

Process each subservice of C<$name> with C<$callback>, printing correct indentations.

=cut
sub traverse($$$) {
    my $self = _obj(shift);
    my ($service, $callback, $indent) = @_;
    $indent ||= 0;

    if (not defined $service) {
        $service = Ubic->root_service;
    }
    elsif (not blessed($service)) {
        $service = Ubic->service($service);
    }
    my $name = $service->full_name;

    if ($service->isa('Ubic::Multiservice')) {
        if ($service->full_name) {
            print ' ' x $indent, $service->full_name, "\n";
            $indent = $indent + 4;
        }
        for my $subservice ($service->services) {
            $self->traverse($subservice, $callback, $indent); # FIXME - rememeber result
        }
    }
    else {
        print(' ' x $indent);
        return $callback->($service);
    }
}

=item B<< print_status($name, $cached_flag) >>

=item B<< print_status($service, $cached_flag) >>

Print status of given service identified by name or by object. If C<$cached_flag> is true, prints status cached in watchdog file.

=cut
sub print_status($$;$$) {
    my $self = _obj(shift);
    my $service = shift;
    my $cached = shift;
    my $results = shift || Ubic::Cmd::Results->new;

    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;
        print "$name\t";
        my $enabled = Ubic->is_enabled($name);
        unless ($enabled) {
            print "off\n";
            $results->add(result('down'));
            return;
        }

        my $status;
        if ($cached) {
            $status = Ubic->cached_status($name);
        }
        else {
            $status = eval { Ubic->status($name) };
            if ($@) {
                $status = result($@);
            }
        }
        if ($status eq 'running') {
            $results->print($status);
        }
        else {
            $results->print($status, 'bad'); # up and not running is always bad
        }
    });

    # TODO - print actual uplevel service's status, it can be service-specific
    if (any { $_->status ne 'running' and $_->status ne 'down' } $results->results) {
        $results->exit_code(3); # some services are not running when they should be
    }
    return $results;
}

=item B<< run($params_hashref) >>

Run given command for given service and exit with LSB-compatible exit code.

Parameters:

=over

=item I<name>

Service's name or arrayref with names.

=item I<command>

Command to execute.

=item I<force>

Force command on protected multiservice.

=back

=cut
sub run {
    my $self = _obj(shift);
    my $params = validate(@_, {
        name => 1,
        command => { type => SCALAR },
        force => 0,
    });
    my @names;
    if (ref $params->{name} eq 'ARRAY') {
        @names = @{$params->{name}};
    }
    else {
        @names = ($params->{name});
    }

    my $command = $params->{command};
    if ($command eq 'status' and $>) {
        print "Not a root, printing cached statuses\n";
    }

    my $results = Ubic::Cmd::Results->new;
    for my $name (@names) {
        $self->_run_impl({ name => $name, command => $command, force => $params->{force}, results => $results });
    }
    exit $results->exit_code;
}

# run and modify results object
sub _run_impl {
    my $self = _obj(shift);
    my $params = validate(@_, {
        name => { type => SCALAR | UNDEF },
        command => { type => SCALAR },
        results => { isa => 'Ubic::Cmd::Results' },
        force => 0,
    });
    my $command = $params->{command};
    my $name = $params->{name};
    my $results = $params->{results};

    if ($command eq 'status' or $command eq 'cached-status') {
        my $cached;
        if ($command eq 'status' and $>) {
            $cached = 1;
        }
        if ($command eq 'cached-status') {
            $cached = 1;
        }
        try {
            $self->print_status($name, $cached, $results);
        }
        catch {
            print STDERR $_;
            $results->exit_code(4); # internal error
        };
        return;
    }

    if ($name and not Ubic->root_service->has_service($name)) {
        print STDERR "Service '$name' not found\n";
        $results->exit_code(5);
        return;
    }

    # FIXME - we're constructing service and drop it to reconstruct later
    # but we need to construct service to check it's custom commands
    my $service = $name ? Ubic->service($name) : Ubic->root_service;

    if ($service->isa('Ubic::Multiservice')) {
        my $screen_name = $name || 'root';
        my $multiop = $service->multiop;
        if ($multiop eq 'forbidden') {
            die "$screen_name multiservice forbids $command";
        }
        elsif ($multiop eq 'protected') {
            unless ($params->{force}) {
                die "$screen_name is protected multiservice, specify --force if you know what you're doing";
            }
        }
        elsif ($multiop ne 'allowed') {
            die "$screen_name has strange multiop value '$multiop'";
        }
    }

    # yes, custom "start" command will override default "start" command, although it's not very useful :)
    # but we need this because of current "logrotate" hack
    if (grep { $_ eq $command } $service->custom_commands) {
        try {
            $self->do_custom_command($service, $command, $results);
        }
        catch {
            print STDERR "'$name $command' error: $_\n";
            $results->exit_code(1); # generic error, TODO - more lsb-specific errors?
        };
        return;
    }

    $command = "force_reload" if $command eq "logrotate"; #FIXME: non LSB command? fix logrotate configs! (yandex-ppb-static-pt, etc...)

    my $method = $command;
    $method =~ s/-/_/g;
    unless (grep { $_ eq $method } qw/ start stop restart try_restart reload force_reload /) {
        $self->usage($command);
    }

    try {
        $self->$method($service, $results);
    }
    catch {
        if ($name) {
            print STDERR "'$name $method' error: $_\n";
        }
        else {
            print STDERR "'$method' error: $_\n";
        }
        $results->exit_code(1); # generic error, TODO - more lsb-specific errors?
    };
    return;
}

=back

=head1 BUGS AND CAVEATS

Interface of this class is unstable and can be changed without further notice.

When in doubt, consider L<Ubic> or system("ubic COMMAND SERVICE") instead.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

