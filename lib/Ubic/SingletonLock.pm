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

=item B<< Ubic::SingletonLock->new($filename, $options) >>

Construct new singleton lock.

Consequent invocations with the same C<$filename> will return the same object if previous object still exists somewhere in process memory.

Any options will be passed directly to L<Ubic::Lockf>.

=cut
sub new {
    my ($class, $file, $options) = validate_pos(@_, 1, 1, 0);

    if ($LOCKS{$file}) {
        return $LOCKS{$file};
    }
    my $lock = lockf($file, $options);
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

=head1 BUGS AND CAVEATS

This module is a part of ubic implementation and shouldn't be used in non-core code.

It passes options blindly to Ubic::Lockf, so following code will not work correctly:

    $lock = Ubic::SingletonLock->new("file", { shared => 1 });
    $lock = Ubic::SingletonLock->new("file"); # this call will just return cached shared lock again

=cut

1;
