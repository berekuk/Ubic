package Ubic::Lockf::Alarm;

# we can't use alarm from Time::HiRes, it don't return current alarm value on perl 5.8.8

sub new ($$) {
    my ($class, $timeout) = @_;
    bless { 'alarm' => alarm($timeout), 'time' => time };
}

sub DESTROY ($) {
    my $self = shift;
    my $alarm;
    if ($self->{alarm}) {
        $alarm = $self->{alarm} + $self->{time} - time;
        $alarm = 1 if $alarm <= 0;
    } else {
        $alarm = 0;
    }
    alarm($alarm);
}

package Ubic::Lockf;
use strict;
use Fcntl qw(:flock);

use Params::Validate;
use POSIX qw(:errno_h);
use Carp;

use base qw(Exporter);

our @EXPORT = qw(lockf);


sub DESTROY ($) {
    my ($self) = @_;
    my $fh = $self->{_fh};
    return unless defined $fh; # already released
    flock $fh, LOCK_UN;
    delete $self->{_fh}; # closes the file if opened by us
}

my %defaults = (
    shared => 0,
    blocking => 1,
    timeout => undef,
    mode => undef,
);

sub lockf ($;$) {
    my ($param, $opts) = validate_pos(@_, 1, 0);
    $opts ||= {};
    $opts = validate(@{ [ $opts ] }, {
        blocking => 0,
        shared => 0,
        silent => 0, # deprecated option, does nothing
        timeout => 0,
        mode => 0,
    });
    $opts = {%defaults, %$opts};

    my ($fh, $fname);
    if (ref $param eq "") { # filename instead of filehandle
        open $fh, ">>", $param or die "Can't open $param: $!";
        $fname = $param;
    } else {
        $fh = $param;
    }

    unless (_lockf($fh, $opts, $fname)) {
        return;
    }

    # don't check chmod success - it can fail and it's ok
    chmod ($opts->{mode}, ($fname || $fh)) if defined $opts->{mode};

    return bless {
        _fh => $fh,
        _fname => $fname,
    };
}

sub _lockf ($$;$) {
    my ($fh, $opts, $fname) = @_;
    $fname ||= ''; # TODO - discover $fname from $fh, it's possible in most cases with some /proc magic

    my $mode = ($opts->{shared} ? LOCK_SH : LOCK_EX);

    if (
        not $opts->{blocking}
        or (defined $opts->{timeout} and not $opts->{timeout}) # timeout=0
    ) {
        return 1 if flock ($fh, $mode | LOCK_NB);
        return 0 if ($! == EWOULDBLOCK);
        croak "flock ".($fname || '')." failed: $!";
    }

    unless (flock ($fh, $mode | LOCK_NB)) {
        my $msg = "$fname already locked, wait...";
        if (-t STDOUT) {
            print $msg;
        }
    } else {
        return 1;
    }

    if ($opts->{timeout}) {
        local $SIG{ALRM} = sub { croak "flock $fname failed: timed out" };
        my $alarm = Ubic::Lockf::Alarm->new($opts->{timeout});
        flock $fh, $mode or die "flock failed: $!";
    } else {
        flock $fh, $mode or die "flock failed: $!";
    }
    return 1;
}

sub name($)
{
    my $self = shift();
    return $self->{_fname};
}

1;

=head1 NAME

Ubic::Lockf - file locker with an automatic out-of-scope unlocking mechanism

=head1 SYNOPSIS

    use Ubic::Lockf;
    $lock = lockf($filehandle);
    $lock = lockf($filename);
    undef $lock; # unlocks either

=head1 DESCRIPTION

C<lockf> is a perlfunc C<flock> wrapper. The lock is autotamically released as soon as the assotiated object is
no longer referenced.

C<lockf_multi> makes non-blocking C<lockf> calls for multiple files and throws and exception if all are locked.

=head1 METHODS

=over

=item B<lockf($file, $options)>

Create an Lockf instance. Always save the result in some variable(s), otherwise the lock will be released immediately.

The lock is automatically released when all the references to the Lockf object are lost. The lockf mandatory parameter
can be either a string representing a filename or a reference to an already opened filehandle. The second optional
parameter is a hash of boolean options. Supported options are:

=over

=item I<shared>

OFF by default. Tells to achieve a shared lock. If not set, an exclusive lock is requested.

=item I<blocking>

ON by default. If unset, a non-blocking mode of flock is used. If this flock fails because the lock is already held by some other process,
C<undef> is returned. If the failure reason is somewhat different, permissions problems or the 
absence of a target file directory for example, an exception is raisen.

=item I<timeout>

Undef by default. If set, specifies the wait timeout for acquiring the blocking lock. The value of 0 is equivalent to blocking => 0 option.

=item I<mode>

Undef by default. If set, a chmod with the specified mode is performed on a newly created file. Ignored when filehandle is passed instead of a filename.

=back

=item B<name()>

Gives the name of the file, as it was when the lock was taken.

=back

=cut
