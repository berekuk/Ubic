package Ubic::ServiceLoader::Base;

# ABSTRACT: abstract base class for service loaders

use strict;
use warnings;

=head1 DESCRIPTION

If you want to add new loader for file with extension C<.foo>, you should implement C<Ubic::ServiceLoader::Ext::foo> module, inheriting from this class and overriding its methods.

=head1 METHODS

=over

=item B<new>

Constructor.

=cut
sub new {
    die "not implemented";
}

=item B<load($file)>

Service loading code. Should return L<Ubic::Service> object based on config file C<$file>.

=cut
sub load {
    die "not implemented";
}

=back

=cut

1;
