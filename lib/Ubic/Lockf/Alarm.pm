package Ubic::Lockf::Alarm;

# we can't use alarm from Time::HiRes, it doesn't return current alarm value on perl 5.8.8 :(

sub new ($$) {
    my ($class, $timeout) = @_;
    bless { 'alarm' => alarm($timeout), 'time' => time };
}

sub DESTROY ($) {
    my $self = shift;
    local $@;
    my $alarm;
    if ($self->{alarm}) {
        $alarm = $self->{alarm} + $self->{time} - time;
        $alarm = 1 if $alarm <= 0;
    } else {
        $alarm = 0;
    }
    alarm($alarm);
}

1;
