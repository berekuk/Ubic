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
            print "HTTP/1.1 500 Disabled\r\n";
        }
        else {
            print "HTTP/1.1 200 OK\r\n";
        }
        print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
        print "disabled\n";
        return;
    }
    my $status = Ubic->cached_status($name)->status; # should read status from static file on disk
    if ($status eq 'running') {
        print "HTTP/1.1 200 OK\r\n";
        print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
        print "ok\n";
        return;
    }
    else {
        if ($options->{noc}) {
            if ($status =~ /^[\w ]+$/) {
                print "HTTP/1.1 500 $status\r\n";
            }
            else {
                # invalid status, fallback to default status message
                print "HTTP/1.1 500 Wrong status\r\n";
            }
        }
        else {
            print "HTTP/1.1 200 OK\r\n";
        }
        print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
        print "$status\n";
        return;
    }
}

sub _traverse_statuses {
    my $service = shift;
    if ($service && !$service->can("services")) {
        my $name = $service->full_name;
        my $status = Ubic->cached_status($name)->status;
        unless (Ubic->is_enabled($name)) { $status = "off"; }
        return $status;
    }
    my @subservices = $service ? $service->services : Ubic->services;
    my $statuses;
    for my $s (@subservices) {
        $statuses->{$s->name} = _traverse_statuses($s);
    }
    return $statuses;
}

sub handle_request {
    my ($self, $cgi) = @_;

    try {
        if ($cgi->path_info eq '/ping') {
            # ping self
            print "HTTP/1.1 200 OK\r\n";
            print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
            print "ok\n";
            return;
        }
        elsif ( $cgi->path_info =~ m{^/noc/(\d+)/?$}) {
            my $port = $1;
            my $name = Ubic::PortMap::port2name($port);
            unless (defined $name) {
                print "HTTP/1.1 404 Not found\r\n";
                print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
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
                print "HTTP/1.1 404 Not found\r\n";
                print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
                print "Service at port '$port' not found\n";
                return;
            }
            _print_status($name);
            return;
        }
        elsif (my ($name) = $cgi->path_info =~ m{^/status/service/(.+?)/?$}) {
            unless (Ubic->has_service($name)) {
                print "HTTP/1.1 404 Not found\r\n";
                print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
                print "Service with name '$name' not found\n";
                return;
            }
            _print_status($name);
        }
        elsif ($cgi->path_info =~ m{^/status/service/?$}) {
            # get all services status in json;
            my $statuses =  _traverse_statuses(); 
            print "HTTP/1.1 200 OK\r\n";
            print "Content-Type: application/json; charset=utf-8\r\n\r\n";
            print encode_json $statuses;
            return;
        }
        else {
            print "HTTP/1.1 404 Not found\r\n";
            print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
            print "Expected /status/service/NAME or /status/port/PORT query\n";
            return;
        }
    }
    catch {
        print "HTTP/1.1 500 Internal error\r\n";
        print "Content-Type: text/plain; charset=utf-8\r\n\r\n";
        print "Error: $_";
    };
}

1;
