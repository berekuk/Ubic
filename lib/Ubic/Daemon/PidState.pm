package Ubic::Daemon::PidState;

use strict;
use warnings;

# ABSTRACT: internal object representing process info stored on disk

=head1 METHODS

=over

=cut

use Params::Validate qw(:all);
use Ubic::Lockf;

use overload '""' => sub {
    my $self = shift;
    return $self->{dir};
};

=item B<new()>

Constructor. Does nothing by itself, doesn't read pidfile and doesn't try to create pid dir.

=cut
sub new {
    my $class = shift;
    my ($dir) = validate_pos(@_, { type => SCALAR });
    return bless { dir => $dir } => $class;
}

=item B<is_empty()>

Check if pid dir doesn't exist yet.

=cut
sub is_empty {
    my ($self) = validate_pos(@_, 1);
    my $dir = $self->{dir};
    if (not -d $dir and not -s $dir) {
        return 1; # empty, old-style pidfile
    }
    if (-d $dir and not -e "$dir/pid") {
        return 1;
    }
    return;
}

=item B<init()>

Create pid dir. After tihs method is called, C<is_empty()> will start to return false value.

=cut
sub init {
    my ($self) = validate_pos(@_, 1);
    my $dir = $self->{dir};
    if (-e $dir and not -d $dir) {
        print "converting $dir to dir\n";
        unlink $dir or die "Can't unlink $dir: $!";
    }
    unless (-d $dir) {
        mkdir $dir or die "Can't create $dir: $!";
    }

}

=item B<read()>

Read daemon info from pidfile.

Returns undef if pidfile not found. Throws exceptions when content is invalid.

=cut
sub read {
    my ($self) = validate_pos(@_, 1);

    my $dir = $self->{dir};

    my $content;
    my $parse_content = sub {
        if ($content =~ /\A pid \s+ (\d+) \n guid \s+ (\d+) (?: \n daemon \s+ (\d+) )? \Z/x) {
            # new format
            return { pid => $1, guid => $2, daemon => $3, format => 'new' };
        }
        else {
            die "invalid pidfile content in pidfile $dir";
        }
    };
    if (-d $dir) {
        # pidfile as dir
        my $open_success = open my $fh, '<', "$dir/pid";
        unless ($open_success) {
            if ($!{ENOENT}) {
                return; # pidfile not found, daemon is not running
            }
            else {
                die "Failed to open '$dir/pid': $!";
            }
        }
        $content = join '', <$fh>;
        return $parse_content->();
    }
    else {
        # deprecated - single pidfile without dir
        if (-f $dir and not -s $dir) {
            return; # empty pidfile - old way to stop services
        }
        open my $fh, '<', $dir or die "Failed to open $dir: $!";
        $content = join '', <$fh>;
        if ($content =~ /\A (\d+) \Z/x) {
            # old format
            return { pid => $1, format => 'old' };
        }
        else {
            return $parse_content->();
        }
    }
}

=item B<lock()>
=item B<lock($timeout)>

Acquire piddir lock. Lock will be nonblocking unless 'timeout' parameter is set.

=cut
sub lock {
    my ($self, $timeout) = validate_pos(@_, 1, { type => SCALAR, default => 0 });

    my $dir = $self->{dir};
    if (-d $dir) {
        # new-style pidfile
        return lockf("$dir/lock", { timeout => $timeout });
    }
    else {
        return lockf($dir, { blocking => 0 });
    }
}

=item B<remove()>

Remove the pidfile from the piddir. C<is_empty()> will still return false.

This method should be called only after lock is acquired via C<lock()> method (TODO - check before removing?).

=cut
sub remove {
    my ($self) = validate_pos(@_, 1);
    my $dir = $self->{dir};

    if (-d $dir) {
        if (-e "$dir/pid") {
            unlink "$dir/pid" or die "Can't remove $dir/pid: $!";
        }
    }
    else {
        unlink $dir or die "Can't remove $dir: $!";
    }
}

=item B<write({ pid => $pid, guid => $guid })>

Write guardian pid and guid into the pidfile.

=cut
sub write {
    my $self = shift;
    my $dir = $self->{dir};
    unless (-d $dir) {
        die "piddir $dir not initialized";
    }
    my $params = validate(@_, {
        pid => 1,
        guid => 1,
    });

    my ($pid, $guid) = @$params{qw/ pid guid /};
    my $self_pid = $$;
    open my $fh, '>', "$dir/pid.new" or die "Can't write '$dir/pid.new': $!";
    print {$fh} "pid $self_pid\n";
    print {$fh} "guid $guid\n";
    print {$fh} "daemon $pid\n";
    $fh->flush;
    close $fh or die "Can't close '$dir/pid.new': $!";
    rename "$dir/pid.new" => "$dir/pid" or die "Can't commit pidfile $dir: $!";
}

=back

=cut

1;
