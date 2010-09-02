#!/usr/bin/perl
package Ubic::Ping;

use strict;
use warnings;

# ABSTRACT: http server which returns service status by it's name or port

use Ubic;
use Ubic::PortMap;
use Params::Validate qw(:all);
use Try::Tiny;

use parent qw(HTTP::Server::Simple::CGI);

sub _print_status($;$) {
    my ($name, $options) = validate_pos(@_, 1, { type => HASHREF, default => {} });

    unless (Ubic->is_enabled($name)) {
        if ($options->{noc}) {
            print "HTTP/1.0 500 Disabled\r\n\r\n";
        }
        else {
            print "HTTP/1.0 200 OK\r\n\r\n";
        }
        print "disabled\n";
        return;
    }
    my $status = Ubic->cached_status($name); # should read status from static file on disk
    if ($status eq 'running') {
        print "HTTP/1.0 200 OK\r\n\r\n";
        print "ok\n";
        return;
    }
    else {
        if ($options->{noc}) {
            if ($status =~ /^[\w ]+$/) {
                print "HTTP/1.0 500 $status\r\n\r\n";
            }
            else {
                # invalid status, fallback to default status message
                print "HTTP/1.0 500 Wrong status\r\n\r\n";
            }
        }
        else {
            print "HTTP/1.0 200 OK\r\n\r\n";
        }
        print "$status\n";
        return;
    }
}

sub handle_request {
    my ($self, $cgi) = @_;

    try {
        if ($cgi->path_info eq '/ping') {
            # ping self
            print "HTTP/1.0 200 OK\r\n\r\n";
            print "ok\n";
            return;
        }
        elsif ( $cgi->path_info =~ m{^/noc/(\d+)/?$}) {
            my $port = $1;
            my $name = Ubic::PortMap::port2name($port);
            unless (defined $name) {
                print "HTTP/1.0 404 Not found\r\n\r\n";
                print "Service at port '$port' not found\n";
                return;
            }
            _print_status($name, { noc => 1 });
            return;
        }
        elsif ($cgi->path_info =~ m{^/status/port/(\d+)/?$}) {
            my $port = $1;
            my $name = Ubic::PortMap::port2name($port);
            unless (defined $name) {
                print "HTTP/1.0 404 Not found\r\n\r\n";
                print "Service at port '$port' not found\n";
                return;
            }
            _print_status($name);
            return;
        }
        elsif (my ($name) = $cgi->path_info =~ m{^/status/service/(.+?)/?$}) {
            unless (Ubic->has_service($name)) {
                print "HTTP/1.0 404 Not found\r\n\r\n";
                print "Service with name '$name' not found\n";
                return;
            }
            _print_status($name);
        }
        else {
            print "HTTP/1.0 404 Not found\r\n\r\n";
            print "Expected /status/name/NAME or /status/port/PORT query\n";
            return;
        }
    }
    catch {
        print "HTTP/1.0 500 Internal error\r\n\r\n";
        print "Error: $_";
    };
}

1;
