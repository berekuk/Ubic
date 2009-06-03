# vim: noet
default:
	perl -Ilib -c bin/ubic-daemon
	mkdir -p man
	set -e; for m in `find lib -name '*.pm'`; do perl -Ilib -c $$m; done
	pod2man bin/ubic-daemon man/ubic-daemon.1
	prove -v t/*.t

install:
	# executable
	mkdir -p -m 0755 $(DESTDIR)/usr/bin/
	cp bin/* $(DESTDIR)/usr/bin/
	# modules
	mkdir -p -m 0755 $(DESTDIR)/usr/share/perl5/
	cp -r lib/* $(DESTDIR)/usr/share/perl5/
	# docs
	mkdir -p -m 0755 $(DESTDIR)/usr/share/man/man1/
	cp man/*.1 $(DESTDIR)/usr/share/man/man1

clean:
	rm -rf man
	rm -rf tfiles

.PHONY: test install clean
