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
use List::MoreUtils qw(all);
use List::Util qw(max);
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

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

=item B<< start($service) >>

=cut
sub start {
    my $self = _obj(shift);
    my $service = shift;

    my @results;
    $self->traverse($service, sub {
        my $service = shift;
        print "Starting ".$service->full_name."... ";
        my $result = eval { Ubic->start($service->full_name) } || result($@);
        $self->print_result($result, $@ ? 'red' : ());
        push @results, $result;
    });
    return $self->stat(\@results);
}


=item B<< stop($service) >>

=cut
sub stop {
    my $self = _obj(shift);
    my $service = shift;
    my @results;

    $self->traverse($service, sub {
        my $service = shift;
        print "Stopping ".$service->full_name."... ";
        my $result = eval { Ubic->stop($service->full_name) } || result($@);
        $self->print_result($result, $@ ? 'red' : ());
        push @results, $result;
    });
    return $self->stat(\@results);
}

=item B<< restart($service) >>

=cut
sub restart {
    my $self = _obj(shift);
    my $service = shift;

    my @results;
    $self->traverse($service, sub {
        my $service = shift;
        print "Restarting ".$service->full_name."... ";
        my $result = eval { Ubic->restart($service->full_name) } || result($@);
        $self->print_result($result, $@ ? 'red' : ());
        push @results, $result;
    });
    return $self->stat(\@results);
}

=item B<< try_restart($service) >>

=cut
sub try_restart {
    my $self = _obj(shift);
    my $service = shift;

    my @results;
    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;
        if (Ubic->is_enabled($name)) {
            print "Restarting $name... ";
            my $result = eval { Ubic->try_restart($name) } || result($@);
            $self->print_result($result, $@ ? 'red' : ());
            push @results, $result;
        }
        else {
            print "$name is down";
            push @results, result('down');
        }
    });
    return $self->stat(\@results);
}

=item B<< reload($service) >>

=cut
sub reload {
    my $self = _obj(shift);
    my $service = shift;

    my @results;
    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;
        if (Ubic->is_enabled($name)) {
            print "Reloading $name... ";
            my $result = eval { Ubic->reload($name) } || result($@);
            $self->print_result($result, $@ ? 'red' : ());
            push @results, $result;
        }
        else {
            print "$name is down\n";
            push @results, result('down');
        }
    });
    for my $result (@results) {
        if ($result->status eq 'broken') {
            die $result;
        }
    }
    return $self->stat(\@results);
}

=item B<< force_reload($name) >>

=cut
sub force_reload {
    my $self = _obj(shift);
    my $service = shift;

    my @results;
    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;
        if (Ubic->is_enabled($name)) {
            print "Reloading $name... ";
            my $result = eval { Ubic->force_reload($name)} || result($@);
            $self->print_result($result, $@ ? 'red' : ());
            push @results, $result;
        }
        else {
            print "$name is down\n";
            push @results, result('down');
        }
    });
    return $self->stat(\@results);
}

=back

=head1 OTHER METHODS

=over

=item B<< do_custom_command($service, $command) >>

Do non-LSB command.

=cut
sub do_custom_command {
    my $self = _obj(shift);
    my ($service, $command) = @_;

    $self->traverse($service, sub {
        my $service = shift;
        Ubic->do_custom_command($service->full_name, $command);
    });
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

=item B<< print_red(@strings) >>

Print given strings in red color if stdout is terminal, and in plain text otherwise.

=cut
sub print_red {
    my $self = _obj(shift);
    if (-t STDOUT) {
        print RED @_;
    }
    else {
        print @_;
    }
}

=item B<< print_green(@strings) >>

Print given strings in green color if stdout is terminal, and in plain text otherwise.

=cut
sub print_green {
    my $self = _obj(shift);
    if (-t STDOUT) {
        print GREEN @_;
    }
    else {
        print @_;
    }
}

=item B<< print_result($result) >>

=item B<< print_result($result, $color) >>

Print given C<Ubic::Result::Class> object.

If C<$color> is specified, it is taken into consideration, otherwise result is printed in green color ("correct") unless it is "broken".

=cut
sub print_result {
    my $self = _obj(shift);
    my ($result, $color) = @_;
    $color ||= '';
    if ($result->status eq 'broken' or $color eq 'red') {
        my $str = "$result";
        chomp $str;
        $self->print_red("$str\n");
    }
    else {
        $self->print_green("$result\n");
    }
}

=item B<< stat(\@results) >>

Print error if some of results are bad, and return correct exit code, understandable by C<_run_impl()>.

=cut
sub stat($$) {
    my $self = _obj(shift);
    my $results = shift;
    my $error = 0;
    if (@$results > 1) {
        my $broken;
        for my $result (@$results) {
            if ($result->status eq 'broken') {
                $broken++;
            }
        }
        if ($broken) {
            $self->print_red("Failed: $broken service(s)\n");
            $error = 1;
        }
    }
    elsif (@$results == 1) {
        if ($results->[0]->status eq 'broken') {
            die $results->[0];
        }
    }
    else {
        # no results, huh?
        die "no services processed";
    }
    return $error;
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
sub print_status($$) {
    my $self = _obj(shift);
    my ($service, $cached) = @_;

    my @results;
    $self->traverse($service, sub {
        my $service = shift;
        my $name = $service->full_name;
        my $enabled = Ubic->is_enabled($name);
        unless ($enabled) {
            print "$name\toff\n";
            push @results, result('down');
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
            $self->print_green("$name\t$status\n");
        }
        else {
            $self->print_red("$name\t$status\n");
        }
        push @results, $status;
    });

    # TODO - print actual uplevel service's status, it can be service-specific
    if (all { $_->status eq 'running' } @results) {
        return result('running');
    }
    elsif (all { $_->status eq 'down' } @results) {
        return result('down');
    }
    else {
        return result('not running'); # at least one subservice is not running
    }
}

=item B<< run($params_hashref) >>

Run given command for given service and exit with LSB-compatible exit code.

Parameters:

=over

=item I<name>

Service's name or arrayref with names.

=item I<command>

Command to execute.

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
    my @exit_codes;
    for my $name (@names) {
        my $exit_code = $self->_run_impl({ name => $name, command => $params->{command}, force => $params->{force} });
        push @exit_codes, $exit_code;
    }
    exit max(@exit_codes);
}

# run and return exit code
sub _run_impl {
    my $self = _obj(shift);
    my $params = validate(@_, {
        name => { type => SCALAR | UNDEF },
        command => { type => SCALAR },
        force => 0,
    });
    my $command = $params->{command};
    my $name = $params->{name};

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
            return 0;
        }
        elsif ($result->status eq 'not running' or $result->status eq 'down') {
            return 3; # see LSB
        }
        else {
            return 150; # application-reserved code
        }
    }

    if ($name and not Ubic->root_service->has_service($name)) {
        print STDERR "Service '$name' not found\n";
        return 5;
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
        eval {
            $self->do_custom_command($service, $command);
        }; if ($@) {
            print STDERR "'$name $command' error: $@\n";
            return 1; # generic error, TODO - more lsb-specific errors?
        }
        else {
            return 0;
        }
    }

    $command = "force_reload" if $command eq "logrotate"; #FIXME: non LSB command? fix logrotate configs! (yandex-ppb-static-pt, etc...)

    my $method = $command;
    $method =~ s/-/_/g;
    unless (grep { $_ eq $method } qw/ start stop restart try_restart reload force_reload /) {
        $self->usage($command);
    }

    my $code = eval {
        $self->$method($service);
    }; if ($@) {
        if ($name) {
            print STDERR "'$name $method' error: $@\n";
        }
        else {
            print STDERR "'$method' error: $@\n";
        }
        return 1; # generic error, TODO - more lsb-specific errors?

    }
    return $code;
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

