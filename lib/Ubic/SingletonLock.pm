package Ubic::SingletonLock;

use strict;
use warnings;

# ABSTRACT: lock which can be safely created several times from the same process without deadlocking

=head1 SYNOPSIS

    use Ubic::SingletonLock;

    $lock = Ubic::SingletonLock->new($file);
    $lock_again = Ubic::SingletonLock->new($file); # this works, unlike Ubic::Lockf which would deadlock at this moment
    undef $lock;

=cut

use Params::Validate;
use Scalar::Util qw(weaken);

use Ubic::Lockf;

our %LOCKS;

=head1 METHODS

=over

=item B<< Ubic::SingletonLock->new($filename) >>

Construct new singleton lock.

Consequent invocations with the same C<$filename> will return the same object if previous object still exists somewhere in process memory.

=cut
sub new {
    my ($class, $file) = validate_pos(@_, 1, 1);

    if ($LOCKS{$file}) {
        return $LOCKS{$file};
    }
    my $lock = lockf($file);
    my $self = bless { file => $file, lock => $lock } => $class;

    $LOCKS{$file} = $self;
    weaken $LOCKS{$file};
    return $self;
}

sub DESTROY {
    my $self = shift;
    local $@;
    delete $LOCKS{ $self->{file} };
}

=back

=cut

1;
