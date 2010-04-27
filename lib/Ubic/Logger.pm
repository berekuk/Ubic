package Ubic::Logger;

use strict;
use warnings;

=head1 NAME

Ubic::Logger - very simple logging functions

=head1 SYNOPSIS

    use Ubic::Logger;
    INFO("hello");
    ERROR("Fire! Fire!");

=head1 FUNCTIONS

=over

=cut

use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

use base qw(Exporter);

our @EXPORT = qw( INFO ERROR );

=item B<INFO(@data)>

Log something.

=cut
sub INFO {
    print '[', scalar(localtime), "]\t", @_, "\n";
}

=item B<ERROR(@data)>

Log some error.

Message will be red if writing to terminal, and will be duplicated into both stdout and stderr otherwise.

=cut
sub ERROR {
    if (-t STDERR) {
        print STDERR RED('[', scalar(localtime), "]\t", @_, "\n");
        unless (-t STDOUT) {
            print STDOUT '[', scalar(localtime), "]\t", @_, "\n";
        }
    }
    else {
        print STDOUT '[', scalar(localtime), "]\t", @_, "\n";
        print STDERR '[', scalar(localtime), "]\t", @_, "\n";
    }
}

=back

=cut

1;

