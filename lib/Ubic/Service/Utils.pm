package Ubic::Service::Utils;

use strict;
use warnings;

=head1 NAME

Ubic::Service::Utils - helpers for custom service authors

=head1 FUNCTIONS

=over

=cut

use Params::Validate qw(:all);
use Time::HiRes qw(sleep);
use Ubic::Result qw(result);
use base qw(Exporter);
our @EXPORT_OK = qw(wait_for_status);

=item B<wait_for_status($params)>

Wait until status will become equal to one of specified values.

Supports customizable retries.

Parameters:

=over

=item I<service>

Service object.

=item I<expect_status>

List of expected statuses. Retries will be stopped when service will return one of given statuses.

=item I<trials>

Number of retries to do.

=item I<step>

Amount of seconds to sleep after first trial. Will be multiplied on trial number, i.e. for C< trials = 4, step = 2>, status will be checked like this: C<check; sleep 2; check; sleep 4; check; sleep 6; check>.

Value is allowed to be float.

=back

=cut
sub wait_for_status {
    my $params = validate(@_, {
        service => { isa => 'Ubic::Service' },
        trials => { type => SCALAR | UNDEF, optional => 1 },
        step => { type => SCALAR | UNDEF, optional => 1 },
        expect_status => { type => SCALAR | ARRAYREF },
    });
    my $trials = $params->{trials} || 1;
    my $step = $params->{step} || 0.1;
    my $service = $params->{service};
    my $expect_status = $params->{expect_status};
    my @expect_status;
    if (ref $expect_status) {
        @expect_status = @$expect_status;
    }
    else {
        @expect_status = ($expect_status);
    }

    my $time = 0;
    my $status;
    for my $trial (1..$trials) {
        $status = result($service->status);
        my $status_str = $status->status;
        last if grep { $_ eq $status_str } @expect_status;
        my $sleep = $step * $trial;
        sleep($sleep);
        $time += $sleep;
    }
    return $status;
}

=back

=head1 AUTHOR

Vyacheslav Matjukhin <mmcleric@yandex-team.ru>

=cut

1;

