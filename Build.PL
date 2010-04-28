#!/usr/bin/perl

use strict;
use warnings;

use 5.008;
use Module::Build;

unless ($^O =~ /linux/i) {
    die "OS unsupported";
}

my $mb = Module::Build->new(
    module_name     => 'Ubic',
    license         => 'perl',
    dist_author     => ['Vyacheslav Matjukhin <mmcleric@yandex-team.ru>'],
    requires        => {
        'Class::Accessor'       => 0,
        'HTTP::Server::Simple'  => 0,
        'List::MoreUtils'       => 0,
        'Params::Validate'      => 0,
        'Perl6::Slurp'          => 0,
        'Try::Tiny'             => 0,
        'LWP::UserAgent'        => 0,
    },
    build_requires => {
        'Test::More'     => 0,
        'Test::Exception' => 0,
    },
    add_to_cleanup => ['tfiles', 'cover_db'],
);

$mb->create_build_script;
