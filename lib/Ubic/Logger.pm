package Ubic::Logger;

use strict;
use warnings;

# ABSTRACT: very simple logging functions

=head1 SYNOPSIS

    use Ubic::Logger;
    INFO("hello");
    ERROR("Fire! Fire!");

=head1 FUNCTIONS

=over

=cut

use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

use parent qw(Exporter);
our @EXPORT = qw( INFO ERROR );

=item B<INFO(@data)>

Log something.

=cut
sub INFO {
    print '[', scalar(localtime), "]\t", @_, "\n";
}

=item B<ERROR(@data)>

Log some error.

Message will be red if writing to terminal.

=cut
sub ERROR {
    my @message = ('[', scalar(localtime), "]\t", @_, "\n");
    if (-t STDOUT) {
        print RED(@message);
    }
    else {
        print @message;
    }
}

=back

=cut

1;

