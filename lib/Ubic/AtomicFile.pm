package Ubic::AtomicFile;

use strict;
use warnings;

# ABSTRACT: atomic file operations

=head1 SYNOPSIS

    use Ubic::AtomicFile;

    Ubic::AtomicFile::store("blah\n" => "/var/lib/blah");

=head1 FUNCTIONS

=over

=item B<store($data, $file)>

Store C<$data> into C<$file> atomically. Temporary C<$file.new> will be created and then renamed to C<$file>.

=cut
sub store($$) {
    my ($data, $file) = @_;

    my $new_file = "$file.new";

    # here is an interesting link explaining why we need to do it this way:
    # https://bugs.launchpad.net/ubuntu/+source/linux/+bug/317781/comments/54
    open my $fh, '>', $new_file or die "Can't open '$new_file' for writing: $!";
    print {$fh} $data or die "Can't print to '$new_file': $!";
    $fh->flush or die "Can't flush '$new_file': $!";
    close $fh or die "Can't close '$new_file': $!";
    rename $new_file => $file or die "Can't rename '$new_file' to '$file': $!";
}
=back

=cut

1;
