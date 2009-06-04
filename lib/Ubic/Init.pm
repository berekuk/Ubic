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

use Ubic;

sub usage {
    print STDERR "Unknown command '$ARGV[0]'\n";
    exit(2); # or exit(3)? see LSB for details
}

sub print_status($;$) {
    my ($name, $cached) = @_;
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
    my ($class) = validate_pos(@_, 1);

    my ($name) = $0 =~ m{^/etc/init\.d/(.+)$} or die "Strange $0";
    my ($command, @args) = @ARGV;
    if ($command eq 'status' or $command eq 'cached-status') {
        @args == 1 or usage();
        my $cached;
        if ($command eq 'status' and $>) {
            print "Not a root, printing cached statuses\n";
            $cached = 1;
        }
        if ($command eq 'cached-status') {
            $cached = 1;
        }
        print_status($args[0], $cached);
        exit;
    }

    # all other commands has no arguments
    usage() if @args;

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
        usage();
    }
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

