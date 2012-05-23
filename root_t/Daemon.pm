package root_t::Daemon;

use strict;
use warnings;

use Ubic::Service::SimpleDaemon;

sub new {
    my ($class, $params) = @_;
    return Ubic::Service::SimpleDaemon->new({
        bin => "echo 'abc' >>tfiles/$params->{name}.result; sleep 10",
        (
            map {
                defined($params->{$_}) ? ($_ => $params->{$_}) : ()
            } qw/ user group daemon_user daemon_group /
        ),
        stdout => "tfiles/$params->{name}.log",
        stderr => "tfiles/$params->{name}.err.log",
        ubic_log => "tfiles/$params->{name}.ubic.log",
    });
}

1;
