package Ubic::Service::ProcManager;

use strict;
use warnings;

=head1 NAME

Ubic::Service::ProcManager - service wrapper for fastcgi services which uses FCGI::ProcManager

=head1 SYNOPSIS

    use Ubic::Service::ProcManager;
    return Ubic::Service::ProcManager->new({
        pidfile => "/tmp/bulca_www.pid",
        socket => "/tmp/fastcgi-bulca-www.sock",
        child => 50,
        log => "/var/log/yandex-bulca-www/fastcgi-restart.log",
        bin => "/usr/bin/bulca_www.pl",
        user => "ppb",
    });

=head1 DESCRIPTION

This service is a simplest ubic wrap for existing procmanager-based fcgi scripts.

It expects scripts to use "-pid X -child Y -s Z" convention, which all PPB scripts are using, because they are all COPYPASTED!

=cut

use base qw(Ubic::Service);
use Params::Validate qw(:all);
use Yandex::X;
use POSIX;

=head1 METHODS

=over

=item C<new($params)>

Parameters (mandatory if not specified otherwise):

=over

=item I<pidfile>

Pid file name.

=item I<socket>

Socket file name.

=item I<child>

Number of children.

=item I<log>

Procmanager log file name (stdout and stderr will both be redirected into it).

=item I<bin>

FastCGI script name. Script must support "-pid X -child Y -s Z" convention.

=item I<user>

User name. If specified, real and effective user identifiers will be changed before execing into fastcgi process (and even before opening I<log>).

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        pidfile => { type => SCALAR },
        socket => { type => SCALAR },
        child => { type => SCALAR, regex => qr/^\d+/ },
        log => { type => SCALAR },
        bin => { type => SCALAR },
        user => { type => SCALAR, optional => 1 },
    });
    return bless $params => $class;
}

sub start {
    my $self = shift;
    $self->stop() if -e $self->{pidfile};
    unless (xfork) {
        # daemonize
        if ($self->{user}) {
            my $uid = getpwnam($self->{user});
            POSIX::setuid($uid);
            POSIX::setsid();
        }
        open STDIN, '/dev/null';
        open STDOUT, ">>", $self->{log} or die "Can't write to $self->{log}: $!";
        open STDERR, ">>", $self->{log} or die "Can't write to $self->{log}: $!"; # TODO - different logs?

        # "true" is a fix for ProcManager oddity - it exists if finds out that it's parent is init(8)
        # calling two processes as "sh" argument forces sh to fork into child and not exec
        xexec(qq#sh -c "true; $self->{bin} -child $self->{child} -s $self->{socket} -pid $self->{pidfile}"#);
    }
    sleep 1; # wait for managers to start workers (FIXME!!)
    return 'started'; # FIXME - check that process actually started!
}

sub stop {
    my $self = shift;
    return 'not running' unless -e $self->{pidfile};
    chomp(my $pid = qx(cat $self->{pidfile}));
    #print "Killing $self->{pidfile} (pid $pid)\n";
    kill 15 => $pid; # never SIGKILL procmanager, it's dangerous!
    for (1..7) {
        # procmanager removes pidfile first, then waits for children to finish
        # i've never seen it to hang if it received signal, so it should be ok
        return 'stopped' unless -e $self->{pidfile};
        sleep 1;
    }
    die "Can't stop, procmanager don't want to exit";
}

sub status {
    my $self = shift;
    if (-e $self->{pidfile}) {
        return 'running';
    }
    else {
        return 'not running';
    }
}

sub user {
    my $self = shift;
    return $self->{user} || 'root';
}

=back

=head1 FUTURE DIRECTIONS

L<Ubic::Service::ProcManager2> will follow, which will do daemonization in proper way.

And after that, L<Ubic::Service::FastCGI>, which will allow us to throw out ProcManager altogether.

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

