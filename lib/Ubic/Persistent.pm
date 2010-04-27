package Ubic::Persistent;

use strict;
use warnings;

=head1 NAME

Ubic::Persistent - simple hash-to-file persistence object

=head1 SYNOPSIS

    use Ubic::Persistent;
    $obj = Ubic::Persistent->new($file); # create object and lock it
    $obj->{x} = 'y';
    $obj->commit; # atomically save file

    $data = Ubic::Persistent->load($file); # { x => 'y' }

=head1 METHODS

=over

=cut

use Data::Dumper;
use Ubic::Lockf;

my $meta = {};

sub _load {
    my ($fname) = @_;

    open my $fh, '<', $fname or die "Can't open $fname: $!";
    my $data;
    local $/;
    my $str = <$fh>;
    eval $str;
    return $data;
}

=item B<< Ubic::Persistent->load($file) >>

Class method. Load data from file without obtaining lock.

=cut
sub load {
    my ($class, $fname) = @_;
    return _load($fname);
}

=item B<< Ubic::Persistent->new($file) >>

Construct new persistent object. It will contain all data from file.

Data will be locked all the time this object exists.

=cut
sub new {
    my ($class, $fname) = @_;
    my $lock = lockf("$fname.lock", { blocking => 1 });

    my $self = {};
    $self = _load($fname) if -e $fname;

    bless $self => $class;
    $meta->{$self} = { lock => $lock, fname => $fname };
    return $self;
}

=item B<< $obj->commit() >>

Write data back on disk.

=cut
sub commit {
    my $self = shift;
    my $fname = $meta->{$self}{fname};
    open my $tmp_fh, '>', "$fname.new" or die "Can't write '$fname.new': $!";

    my $dumper = Data::Dumper->new([ {%$self} ], [ qw(data) ]);
    $dumper->Terse(0); # somebody could enable terse mode globally
    print {$tmp_fh} $dumper->Dump;
    close $tmp_fh or die "Can't write to '$fname.new': $!";
    rename "$fname.new" => $fname or die "Can't rename '$fname.new' to '$fname': $!";
}

sub DESTROY {
    my $self = shift;
    delete $meta->{$self};
}

1;

