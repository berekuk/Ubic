#!/usr/bin/perl
# Copyright (c) 2009 Yandex.ru

package Yandex::Bulca::WWW;

=head1 NAME

fastcgi.pl - simplest FastCGI script for testing Ubic::Service::ProcManager

=cut

use strict;
use warnings;

use FCGI;
use FCGI::ProcManager;

use Getopt::Long 2.33;
use Pod::Usage;
use HTTP::Response;

my $socket_file;
my $pid_file;
my $child = 1;

GetOptions(
        "s=s"  => \$socket_file,
        "child=i" => \$child,
        "pid=s" => \$pid_file,
) or pod2usage(2);
pod2usage(1) unless defined $socket_file and defined $pid_file;

# main fcgi loop begins

use IO::Handle;
STDOUT->autoflush(1);
STDERR->autoflush(1);

my $proc_manager = FCGI::ProcManager->new({
        n_processes => $child,
        pid_fname => $pid_file,
        die_timeout => 3,
});

my $socket_fno = FCGI::OpenSocket($socket_file, 10000) or die "can't open socket '$socket_file'";
my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $socket_fno);

$proc_manager->pm_change_process_name('ubic-test-fcgi-manager'); # doesn't work, huh
$proc_manager->pm_manage();
$proc_manager->pm_change_process_name('ubic-test-fcgi-worker');

while ($request->Accept() >= 0) {
    $proc_manager->pm_pre_dispatch();

    my $resp;
    $resp = HTTP::Response->new(200, 'OK', undef, 'hi there');
    print $resp->as_string("\r\n");

    $proc_manager->pm_post_dispatch();
}
