package t::Utils::IgnoreWarnGuard;

use strict;
use warnings;

sub new {
    my ($class, $regex) = @_;
    $ENV{IGNORE_WARN} = $regex;
    my $prev_sig = $SIG{__WARN__};
    $SIG{__WARN__} = sub {
        return if $_[0] =~ $regex;
        if (ref $prev_sig and ref $prev_sig eq 'CODE') {
            $prev_sig->(@_);
        }
        else {
            warn @_;
        }
    };
    return bless { prev_sig => $prev_sig } => $class;
}

sub DESTROY {
    my $self = shift;
    $SIG{__WARN__} = $self->{prev_sig} if $self->{prev_sig};
    delete $ENV{IGNORE_WARN};
}

1;
