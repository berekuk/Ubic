package Ubic::Admin::Setup;

# ABSTRACT: this module handles ubic setup: asks user some questions and configures your system

=head1 DESCRPITION

This module guides user through ubic configuration process.

=head1 INTERFACE SUPPORT

This is considered to be a non-public class. Its interface is subject to change without notice.

=head1 FUNCTIONS

=over

=cut

use strict;
use warnings;

use Getopt::Long 2.33;
use Carp;

use Ubic::Settings;
use Ubic::Settings::ConfigFile;

my $batch_mode;
my $quiet;

=item B<< print_tty(@) >>

Print something to terminal unless quiet mode or batch mode is enabled.

=cut
sub print_tty {
    print @_ unless $quiet or $batch_mode;
}

=item B<< prompt($description, $default) >>

Ask user a question, assuming C<$default> as a default.

This function is stolen from ExtUtils::MakeMaker with some modifications.

=cut
sub prompt ($;$) {
    my($mess, $def) = @_;
    Carp::confess("prompt function called without an argument")
        unless defined $mess;

    return $def if $batch_mode;

    my $isa_tty = -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT));
    Carp::confess("tty not found") if not $isa_tty;

    $def = defined $def ? $def : "";

    local $| = 1;
    local $\ = undef;
    print "$mess ";

    my $ans;
    if (not $isa_tty and eof STDIN) {
        print "$def\n";
    }
    else {
        $ans = <STDIN>;
        if( defined $ans ) {
            chomp $ans;
        }
        else { # user hit ctrl-D
            print "\n";
        }
    }

    return (!defined $ans || $ans eq '') ? $def : $ans;
}

=item B<< prompt_str($description, $default) >>

Ask user for a string.

=cut
sub prompt_str {
    my ($description, $default) = @_;
    return prompt("$description [$default]", $default);
}

=item B<< prompt_bool($description, $default) >>

Ask user a yes/no question.

=cut
sub prompt_bool {
    my ($description, $default) = @_;
    my $yn = ($default ? 'y' : 'n');
    my $yn_hint = ($default ? 'Y/n' : 'y/N');
    my $result = prompt("$description [$yn_hint]", $yn);
    if ($result =~ /^y/i) {
        return 1;
    }
    return;
}

=item B<< xsystem(@command) >>

Invoke C<system> command, throwing exception on errors.

=cut
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

=item B<< setup() >>

Perform setup.

=cut
sub setup {

    my $opt_reconfigure;
    my $opt_service_dir;
    my $opt_data_dir;
    my $opt_log_dir;
    my $opt_default_user = 'root';
    my $opt_sticky_777 = 1;
    my $opt_install_services = 1;
    my $opt_crontab = 1;

    GetOptions(
        'batch-mode' => \$batch_mode,
        'quiet' => \$quiet,
        'reconfigure!' => \$opt_reconfigure,
        'service-dir=s' => \$opt_service_dir,
        'data-dir=s' => \$opt_data_dir,
        'log-dir=s' => \$opt_log_dir,
        'default-user=s' => \$opt_default_user,
        'sticky-777!' => \$opt_sticky_777,
        'install-services!' => \$opt_install_services,
        'crontab!' => \$opt_crontab,
    ) or die "Getopt failed";

    die "Unexpected arguments '@ARGV'" if @ARGV;

    eval { Ubic::Settings->check_settings };
    unless ($@) {
        my $go = prompt_bool("Looks like ubic is already configured, do you want to reconfigure?", $opt_reconfigure);
        return unless $go;
        print_tty "\n";
    }

    print_tty "Ubic can be installed either in your home dir or into standard system paths (/etc, /var).\n";
    print_tty "You need to be root to install it into system.\n";

    my $is_root = ( $> ? 0 : 1 );
    if ($is_root) {
        my $ok = prompt_bool("You are root, install into system?", 1);
        return unless $ok;
    }
    else {
        my $ok = prompt_bool("You are not root, install locally?", 1);
        return unless $ok;
    }

    my $home;
    unless ($is_root) {
        $home = $ENV{HOME};
        unless (defined $home) {
            die "Can't find your home!";
        }
        unless (-d $home) {
            die "Can't find your home dir '$home'!";
        }
    }

    print_tty "\nService dir is a directory with descriptions of your services.\n";
    my $default_service_dir = ($is_root ? '/etc/ubic/service' : "$home/ubic/service");
    $default_service_dir = $opt_service_dir if defined $opt_service_dir;
    my $service_dir = prompt_str("Service dir?", $default_service_dir);

    print_tty "\nData dir is a directory into which ubic stores all of its data: locks,\n";
    print_tty "status files, tmp files.\n";
    my $default_data_dir = ($is_root ? '/var/lib/ubic' : "$home/ubic/data");
    $default_data_dir = $opt_data_dir if defined $opt_data_dir;
    my $data_dir = prompt_str("Data dir?", $default_data_dir);

    print_tty "\nLog dir is a directory into which ubic.watchdog will write its logs.\n";
    print_tty "(Your own services are free to write logs wherever they want.)\n";
    my $default_log_dir = ($is_root ? '/var/log/ubic' : "$home/ubic/log");
    $default_log_dir = $opt_log_dir if defined $opt_log_dir;
    my $log_dir = prompt_str("Log dir?", $default_log_dir);

    # TODO - sanity checks?

    my $default_user;
    if ($is_root) {
        print_tty "\nUbic services can be started from any user.\n";
        print_tty "Some services don't specify the user from which they must be started.\n";
        print_tty "Default user will be used in this case.\n";
        $default_user = prompt_str("Default user?", $opt_default_user);
    }
    else {
        print_tty "\n";
        $default_user = getpwuid($>);
        unless (defined $default_user) {
            die "Can't get login (uid '$>')";
        }
        print_tty "You're using local installation, so default service user will be set to '$default_user'.\n";
    }

    my $enable_1777;
    if ($is_root) {
        print_tty "\nSystem-wide installations usually need to store service-related data\n";
        print_tty "into data dir for different users. For non-root services to work\n";
        print_tty "1777 grants for some data dir subdirectories is required.\n";
        print_tty "(1777 grants means that everyone is able to write to the dir,\n";
        print_tty "but only file owners are able to modify and remove their files.)\n";
        print_tty "There are no known security issues with this approach, but you have\n";
        print_tty "to decide for yourself if that's ok for you.\n";

        $enable_1777 = prompt_bool("Enable 1777 grants for data dir?", $opt_sticky_777);
    }

    my $install_services;
    {
        print_tty "There are three standard services in ubic service tree:\n";
        print_tty " - ubic.watchdog (universal watchdog)\n";
        print_tty " - ubic.ping (http service status reporter)\n";
        print_tty " - ubic.update (helper process which updates service portmap, used by ubic.ping service)\n";
        print_tty "If you'll choose to install them, ubic.watchdog will be started automatically\n";
        print_tty "and two other services will be initially disabled.\n";
        $install_services = prompt_bool("Do you want to install standard services?", $opt_install_services);
    }

    my $enable_crontab;
    {
        print_tty "\n'ubic.watchdog' is a service which checks all services and restarts them if\n";
        print_tty "there are any problems with their statuses.\n";
        print_tty "It is very simple and robust, but since it's important that watchdog never\n";
        print_tty "goes down, we recommended to install the cron job which checks watchdog itself.\n";
        $enable_crontab = prompt_bool("Install watchdog's watchdog as a cron job?", $opt_crontab);
    }

    my $config_file = ($is_root ? '/etc/ubic/ubic.cfg' : "$home/.ubic.cfg");

    {
        print_tty "\nThat's all I need to know.\n";
        print_tty "If you proceed, all necessary directories will be created,\n";
        print_tty "and configuration file will be stored into $config_file.\n";
        my $run = prompt_bool("Complete setup?", 1);
        return unless $run;
    }

    print "Installing dirs...\n";

    xsystem('mkdir', '-p', '--', $service_dir);
    xsystem('mkdir', '-p', '--', $data_dir);
    xsystem('mkdir', '-p', '--', $log_dir);

    for my $subdir (qw[
        status simple-daemon/pid lock ubic-daemon tmp watchdog/lock watchdog/status
    ]) {
        xsystem('mkdir', '-p', '--', "$data_dir/$subdir");
        xsystem('chmod', '1777', '--', "$data_dir/$subdir") if $enable_1777;
    }

    xsystem('mkdir', '-p', '--', "$service_dir/ubic");

    if ($install_services) {
        my $add_service = sub {
            my ($name, $content) = @_;
            print "Installing ubic.$name service...\n";

            my $file = "$service_dir/ubic/$name";
            open my $fh, '>', $file or die "Can't write to '$file': $!";
            print {$fh} $content or die "Can't write to '$file': $!";
            close $fh or die "Can't close '$file': $!";
        };

        $add_service->(
            'ping',
            "use Ubic::Ping::Service;\n"
            ."Ubic::Ping::Service->new;\n"
        );

        $add_service->(
            'watchdog',
            "use Ubic::Service::SimpleDaemon;\n"
            ."Ubic::Service::SimpleDaemon->new(\n"
            ."bin => [ 'ubic-periodic', '--rotate-logs', '--period=60', '--stdout=$log_dir/watchdog.log', '--stderr=$log_dir/watchdog.err.log', 'ubic-watchdog' ],\n"
            .");\n"
        );

        $add_service->(
            'update',
            "use Ubic::Service::SimpleDaemon;\n"
            ."Ubic::Service::SimpleDaemon->new(\n"
            ."bin => [ 'ubic-periodic', '--rotate-logs', '--period=60', '--stdout=$log_dir/update.log', '--stderr=$log_dir/update.err.log', 'ubic-update' ],\n"
            .");\n"
        );
    }

    if ($enable_crontab) {
        print "Installing cron jobs...\n";
        my $old_crontab = qx(crontab -l);
        if ($?) {
            die "crontab -l failed";
        }
        if ($old_crontab =~ /\subic-watchdog\b/) {
            print "Looks like you already have ubic commands in your crontab.\n";
        }
        else {
            open my $fh, '|-', 'crontab -' or die "Can't run 'crontab -': $!";
            my $printc = sub {
                print {$fh} @_ or die "Can't write to pipe: $!";
            };
            $printc->($old_crontab."\n");
            $printc->("* * * * * ubic-watchdog ubic.watchdog    >>/dev/null 2>>/dev/null\n");
            close $fh or die "Can't close pipe: $!";
        }
    }

    print "Installing $config_file...\n";
    Ubic::Settings::ConfigFile->write($config_file, {
        service_dir => $service_dir,
        data_dir => $data_dir,
        default_user => $default_user,
    });

    if ($install_services) {
        print "Starting ubic.watchdog...\n";
        xsystem('ubic start ubic.watchdog');
    }

    print "Installation complete.\n";
}

=back

=head1 SEE ALSO

L<ubic-admin> - command-line script which calls this module

=cut

1;
