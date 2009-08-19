package Ubic::Init;

use strict;
use warnings;

=head1 NAME

Ubic::Init - helps to write /etc/init.d/ script which uses ubic

=head1 SYNOPSIS

    # /etc/init.d/something:
    use Ubic::Init;
    Ubic::Init->run;

=cut

use Params::Validate qw(:all);
use Scalar::Util qw(blessed);

use Ubic;

sub new {
    my $class = shift;
    my $self = validate(@_, {
        name => { type => SCALAR },
        command => { type => SCALAR, optional => 1 },
        args => { type => ARRAYREF, default => []},
    });
    return bless $self => $class;
}

our $SINGLETON;
sub obj {
    my ($param) = validate_pos(@_, 1);
    if (blessed($param)) {
        return $param;
    }
    if ($param eq 'Ubic::Init') {
        # method called as a class method => singleton
        my ($name) = $0 =~ m{^/etc/init\.d/(.+)$} or die "Strange $0";
        my ($command, @args) = @ARGV;
        $SINGLETON ||= Ubic->new({
            name => $name,
            ($command ? (command => $command) : ()),
            command => $command,
            (@args ?  (args => \@args) : ()),
        });
        return $SINGLETON;
    }
    die "Unknown argument '$param'";
}

sub usage {
    my $self = obj(shift);
    print STDERR "Unknown command '$self->{command}'\n";
    exit(2); # or exit(3)? see LSB for details
}

sub print_status($;$) {
    my $self = obj(shift);
    my ($cached) = @_;

    my $name = $self->{name};

    my $enabled = Ubic->is_enabled($name);
    if ($enabled) {
        my $status = ($cached ? Ubic->cached_status($name) : Ubic->status($name));
        if ($status eq 'running') {
            my $msg;
            $msg .= "\e[32m" if -t STDOUT;
            $msg .= "$name\t$status\n";
            $msg .= "\e[0m" if -t STDOUT;
            print $msg;
        }
        else {
            my $msg;
            $msg .= "\e[31m" if -t STDOUT;
            $msg .= "$name\t$status\n";
            $msg .= "\e[0m" if -t STDOUT;
            print $msg;
        }
    }
    else {
        print "$name\toff\n";
    }
}

# FIXME - separate all command actions into different subs (or methods)
sub run {
    my $self = obj(shift);
    my $command = $self->{command};
    my @args = @{$self->{args}};
    my $name = $self->{name};

    unless (defined $command) {
        die "No command specified";
    }

    if ($command eq 'status' or $command eq 'cached-status') {
        @args == 1 or $self->usage();
        my $cached;
        if ($command eq 'status' and $>) {
            print "Not a root, printing cached statuses\n";
            $cached = 1;
        }
        if ($command eq 'cached-status') {
            $cached = 1;
        }
        $self->print_status($args[0], $cached);
        return;
    }

    # all other commands has no arguments
    $self->usage() if @args;

    # all other commands should be running from root
    if ($>) {
        print STDERR "Permission denied\n";
        exit(4); # see LSB
    }

    if ($command eq 'start') {
        print "Starting $name... ";
        my $result = Ubic->start($name);
        print "$result\n";
        exit;
    }
    elsif ($command eq 'stop') {
        print "Stopping $name... ";
        my $result = Ubic->stop($name);
        print "$result\n";
        exit;
    }
    elsif ($command eq 'restart') {
        print "Restarting $name... ";
        my $result = Ubic->restart($name);
        print "$result\n";
        exit;
    } # remaining commands should print "$name is down" if service is down; FIXME - get rid of copypaste
    elsif ($command eq 'try-restart') {
        if (Ubic->is_enabled($name)) {
            print "Restarting $name... ";
            my $result = Ubic->try_restart($name);
            print "$result\n";
            exit;
        }
        else {
            print "$name is down";
        }
    }
    elsif ($command eq 'reload') {
        if (Ubic->is_enabled($name)) {
            print "Reloading $name... ";
            my $result = Ubic->reload($name);
            print "$result\n";
            exit;
        }
        else {
            print "$name is down";
        }
    }
    elsif ($command eq 'force-reload') {
        if (Ubic->is_enabled($name)) {
            print "Reloading $name... ";
            my $result = Ubic->force_reload($name);
            print "$result\n";
            exit;
        }
        else {
            print "$name is down";
        }
    }
    else {
        $self->usage();
    }
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

