package t::Utils;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw( ignore_warn rebuild_tfiles xsystem xfork slurp );

use Carp;

if ($ENV{IGNORE_WARN}) {
    # parent process has set warn regex
    ignore_warn($ENV{IGNORE_WARN});
}

sub rebuild_tfiles {
    system('rm -rf tfiles') and die "Can't remove tfiles";
    mkdir 'tfiles' or die "Can't create tfiles: $!";
}

sub ignore_warn {
    my $regex = shift;
    return t::Utils::WarnIgnore->new($regex);
}

sub xsystem {
    local $! = local $? = 0;
    return if system(@_) == 0;

    my @msg;
    if ($!) {
        push @msg, "error ".int($!)." '$!'";
    }
    if ($? > 0) {
        push @msg, "kill by signal ".($? & 127) if ($? & 127);
        push @msg, "core dumped" if ($? & 128);
        push @msg, "exit code ".($? >> 8) if $? >> 8;
    }
    die join ", ", @msg;
}

sub xfork {
    my $pid = fork;
    croak "fork failed: $!" unless defined $pid;
    return $pid;
}

sub slurp {
    my $file = shift;
    open my $fh, '<', $file or die "Can't open $file: $!";
    return do { local $/; <$fh> };
}

package t::Utils::WarnIgnore;

sub new {
    my ($class, $regex) = @_;
    $ENV{IGNORE_WARN} = $regex;
    my $prev_sig = $SIG{__WARN__};
    $SIG{__WARN__} = sub {
        return if $_[0] =~ $regex;
        if (ref $prev_sig and ref $prev_sig eq 'CODE') {
            $prev_sig->(@_);
        }
    };
    return bless { prev_sig => $prev_sig } => $class;
}

sub DESTROY {
    my $self = shift;
    $SIG{__WARN__} = $self->{prev_sig} if $self->{prev_sig};
    delete $ENV{IGNORE_WARN};
}

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

