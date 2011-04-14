Ubic
===========================

Ubic is a flexible perl-based service manager.

INSTALLATION

Run 'cpan -i Ubic && ubic-admin setup' to install Ubic.

We also provide .deb packages for Debian/Ubuntu. Latest .deb package can be downloaded from ppa:berekuk/ubic (see <https://launchpad.net/~berekuk/+archive/ubic> for details).

Debian package build can be reproduced with this command:
    dzil build && cd Ubic* && debuild

If you'll write ebuilds for Gentoo or specs for RPM-based systems, please contribute them back :)

DOCUMENTATION

After installing, you can find documentation for this module using perldoc
and man commands.

    man ubic
    perldoc Ubic

You can also look for information at:

* [Github Wiki](http://github.com/berekuk/Ubic/wiki)
* [Search CPAN](http://search.cpan.org/dist/Ubic/)

SUPPORT

Our mailing list is <ubic-perl@googlegroups.com>. Send an empty message to <ubic-perl+subscribe@googlegroups.com> to subscribe.

These is also an IRC channel: <irc://irc.perl.org#ubic>.

COPYRIGHT AND LICENCE

Copyright (c) 2009-2011 Yandex LTD. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See <http://www.perl.com/perl/misc/Artistic.html>

