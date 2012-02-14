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

  if ($arr[0] =~ /^HTTP\/([0-9\.]+)\s+([0-9]{3})\s+(?=([^\r\n]*))?/i) {
    $arr[2] =~ s/\n//;
    return {ver => $1, code => $2, status => $3, body => $arr[2]};
  }
  else {
    return {error => 'This is not html'};
  }
}

1;
