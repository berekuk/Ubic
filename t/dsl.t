use strict;
use warnings;
use Test::More;

use Ubic::ServiceLoader;

plan skip_all => 'cannot read t/service/dsl' unless -r 't/service/dsl';

my $s = Ubic::ServiceLoader->load('t/service/dsl');

isa_ok $s, 'Ubic::Service::SimpleDaemon';
is $s->{bin}, 'tagtimed.pl', 'correct constructor args';
done_testing;
