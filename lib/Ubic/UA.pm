package Ubic::UA;

# ABSTRACT: tiny http client

use strict;
use warnings;
use IO::Socket;

sub new {
    my $class = shift;
    my %arg   = @_;

    my $self = {};
    $self->{timeout} = $arg{timeout} || 10;
    return bless $self => $class;
}

sub get {
    my $self = shift;
    my ($url) = @_;

    unless ($url) {
        return {error => 'Not set url'};
    }

    my ($scheme, $authority, $path, $query, undef) = $url
    =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $authority,
        Proto    => 'tcp',
        Timeout  => $self->{timeout}
    ) or return {error => $@};
    $socket->autoflush(1);
    $path .= '?' . $query if $query;
    print $socket "GET $path HTTP/1.0\r\n\r\n";
    my @arr = <$socket>;
    close $socket;

    my $status_line = shift @arr;
    my @headers;
    while (my $line = shift @arr) {
        last if $line eq "\r\n";
        $line =~ s/\r\n//;
        push @headers, $line;
    }

    if ($status_line =~ /^HTTP\/([0-9\.]+)\s+([0-9]{3})\s+(?=([^\r\n]*))?/i) {
        my ($ver, $code, $status) = ($1, $2, $3);
        return {
            ver => $ver,
            code => $code,
            status => $status,
            body => join('', @arr),
            headers => \@headers,
        };
    }
    else {
        return { error => 'Invalid http response' };
    }
}

1;
