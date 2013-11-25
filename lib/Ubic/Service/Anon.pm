package Ubic::Service::Anon;

=head1 NAME

Ubic::Service::Anon - Standalone service sugar

=head1 SYNOPSIS

    $ ./t/bin/anon-service
    $ ./t/bin/anon-service [start|stop|restart|status]

=head1 DESCRIPTION

This name is subject for change. I just had to put the example code
somewhere.

=cut

use strict;
use warnings;

require Moo;
require Moo::Role;

my $ANON = 1;

sub import {
    my $class = shift;
    my @caller = caller;
    my $service_class = $class->_service_class(@caller);
    my $service = $service_class->new;
 
    strict->import;
    warnings->import;
 
    no strict 'refs';

    *{"$caller[0]\::extends"} = sub {
        Moo->_set_superclasses($service_class, @_);
        Moo->_maybe_reset_handlemoose($service_class);
        return;
    };

    *{"$caller[0]\::cmd"} = sub {
        my($name, $code) = @_;
        $service->_cmd->{$name} = $code;
        return $service if wantarray;
        exit _run($service, @ARGV);
    };

    *{"$caller[0]\::service"} = \$service;

    *{"$caller[0]\::with"} = sub {
        Moo::Role->apply_roles_to_package($service_class, @_);
        Moo->_maybe_reset_handlemoose($service_class);
        return;
    };
}

sub _run {
    my($self, $action, @args) = @_;

    if($action and $self->_cmd->{$action}) {
        return $self->_cmd->{$action}->($self, @args);
    }
    else {
        local $" = '|';
        printf "Usage: %s [%s]\n", $0, join '|', keys %{ $self->_cmd };
        return 0;
    }
}

sub _service_class {
    my($class, @caller) = @_;
    my $service_class = $caller[1];
 
    $service_class =~ s!\W!_!g;
    $service_class = join '::', $class, "_${ANON}_", $service_class;
    $ANON++;
 
    eval <<"    PACKAGE" or die "Failed to generate service class: $@";
        package $service_class;
        use Moo;
        has _cmd => ( is => 'ro', default => sub { +{} } );
        1;
    PACKAGE

    return $service_class;
}

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
