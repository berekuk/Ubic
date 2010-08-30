Ubic
===========================

Ubic is a flexible perl-based service manager.

INSTALLATION

Full ubic installation requires crontab, configs and running watchdog,
so installing through 'cpan -i' is currently incomplete.

For full install on Debian/Ubuntu, last .deb package can be downloaded at http://github.com/berekuk/Ubic/downloads.
Debian package build can be reproduced with this command:
    dzil build && cp -r debian Ubic*/ && cd Ubic* && debuild

For non-Debian systems, basically you'll need to:
- copy all files from etc/ into /etc
- copy debian/ubic.logrotate into /etc/logrotate.d/ubic and debian/ubic.cron.d into /etc/cron.d/ubic
- create all dirs from debian/ubic.dirs
- run commands from debian/ubic.postinst

If you'll write ebuilds for Gentoo or specs for RPM-based systems, please contribute them back :)

DOCUMENTATION

After installing, you can find documentation for this module using perldoc
and man commands.

    man ubic
    perldoc Ubic

You can also look for information at:

    Github Wiki:
        http://github.com/berekuk/Ubic/wiki

    Search CPAN
        http://search.cpan.org/dist/Ubic/

SUPPORT

Our mailing list is ubic-perl@googlegroups.com. Send an empty message to ubic-perl+subscribe@googlegroups.com to subscribe.

These is also an IRC channel: irc://irc.perl.org#ubic.

COPYRIGHT AND LICENCE

Copyright (c) 2009-2010 Yandex LTD. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See <http://www.perl.com/perl/misc/Artistic.html>

