# Ubic

Ubic is a flexible perl-based service manager.

## Installation

Run 'cpan -i Ubic && ubic-admin setup' to install Ubic.

We also provide .deb packages for Debian/Ubuntu. Latest .deb package can be downloaded from ppa:berekuk/ubic (see <https://launchpad.net/~berekuk/+archive/ubic> for details).

Debian package build can be reproduced with this command:
    dzil build && cd Ubic* && cp -r ../debian . && debuild

If you'll write ebuilds for Gentoo or specs for RPM-based systems, please contribute them back :)

## Documentation

After installing, you can find documentation for this module using perldoc
and man commands.

    man ubic
    perldoc Ubic

You can also look for information at:

* [Github Wiki](http://github.com/berekuk/Ubic/wiki)
* [CPAN](https://metacpan.org/release/Ubic)

## Support

Our IRC channel: <irc://irc.perl.org#ubic>.

There is also a low-volume mailing list is <ubic-perl@googlegroups.com>. Send an empty message to <ubic-perl+subscribe@googlegroups.com> to subscribe.


## Copyright and licence

Copyright (c) 2009-2011 Yandex LTD. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See <http://www.perl.com/perl/misc/Artistic.html>

## Donate

I don't actually need donations. I get paid at my $job for hacking on Ubic
anyways.
But I like Flattr's idea, so why not.

You can also +1 Ubic on [MetaCPAN](https://metacpan.org/release/Ubic) if you like it.

[![Flattr this git repo](http://api.flattr.com/button/flattr-badge-large.png)](https://flattr.com/submit/auto?user_id=berekuk&url=http://github.com/berekuk/Ubic&title=Ubic&language=en_GB&tags=github&category=software)
