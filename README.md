Ubic
===========================

Toolkit for writing daemons, init scripts and services in perl.

INSTALLATION

Full ubic installation requires crontab, configs and running watchdog,
so installing through 'cpan -i' is currently incomplete.

For full install on Debian/Ubuntu, use standard debian packaging commands:
	debuild && sudo debi

For non-Debian systems, basically you'll need to:
 - copy all files from etc/ into /etc
 - copy debian/ubic.logrotate into /etc/logrotate.d/ubic and debian/ubic.cron.d into /etc/cron.d/ubic
 - create all dirs from debian/ubic.dirs
 - run commands from debian/ubic.postinst

If you'll write ebuilds for Gentoo and specs for RPM-based systems, please contribute them back :)

SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module using perldoc
and man commands.

    man ubic
    perldoc Ubic

You can also look for information at:

    Github
        http://github.com/berekuk/ubic

    Search CPAN
        http://search.cpan.org/dist/Ubic/

COPYRIGHT AND LICENCE

Copyright (c) 2009-2010 Yandex LTD. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See <http://www.perl.com/perl/misc/Artistic.html>

