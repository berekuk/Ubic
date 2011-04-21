package t::Utils;

use strict;
use warnings;

use t::Utils::IgnoreWarn;
use Params::Validate qw(:all);

use parent qw(Exporter);
our @EXPORT = qw(
    ignore_warn rebuild_tfiles xsystem xfork slurp local_ubic
);

use Carp;
use Cwd;

sub import {
    my $class = shift;
    if ($ENV{PERL5LIB}) {
        $ENV{PERL5LIB} = $ENV{PERL5LIB}.":".getcwd()."/lib";
    }
    else {
        $ENV{PERL5LIB} = getcwd()."/lib";
    }

    delete $ENV{$_} for grep { /^UBIC/ } %ENV; # in case user uses env to configure local ubic instance

    __PACKAGE__->export_to_level(1, @_);
}

sub rebuild_tfiles {
    system('rm -rf tfiles') and die "Can't remove tfiles";
    mkdir 'tfiles' or die "Can't create tfiles: $!";
}

sub xsystem {
    local $! = local $? = 0;
    return if system(@_) == 0;

    my @msg;
    if ($!) {
        push @msg, "error ".int($!)." '$!'";
    }
    if ($? > 0) {
        push @msg, "kill by signal ".($? & 127) if ($? & 127);
        push @msg, "core dumped" if ($? & 128);
        push @msg, "exit code ".($? >> 8) if $? >> 8;
    }
    die join ", ", @msg;
}

sub xfork {
    my $pid = fork;
    croak "fork failed: $!" unless defined $pid;
    return $pid;
}

sub slurp {
    my $file = shift;
    open my $fh, '<', $file or die "Can't open $file: $!";
    return do { local $/; <$fh> };
}

our $local_ubic;
sub local_ubic {
    my $params = validate(@_, {
        service_dirs => { type => ARRAYREF, default => ['t/service/common', 'etc/ubic/service'] },
        default_user => {
            type => SCALAR,
            default => $ENV{LOGNAME} || $ENV{USERNAME},
        },
    });

    xsystem('mkdir tfiles/service');
    for my $dir (@{ $params->{service_dirs} }) {
        xsystem('cp', '-r', '--', glob("$dir/*"), 'tfiles/service/');
    }

    require Ubic;
    Ubic->set_data_dir('tfiles/ubic');
    Ubic->set_service_dir('tfiles/service');
    Ubic->set_default_user($params->{default_user});
}

1;
