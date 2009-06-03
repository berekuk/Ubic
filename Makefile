# vim: noet
test:
	set -e; for f in bin/* www/*; do perl -Ilib -c $$f; done
	set -e; for m in `find lib -name '*.pm'`; do perl -Ilib -c $$m; done
	prove -v t/*.t

build-man:
	mkdir -p man
	pod2man bin/ubic-daemon man/ubic-daemon.1

install: build-man
	# executable
	mkdir -p -m 0755 $(DESTDIR)/usr/bin/
	cp bin/* $(DESTDIR)/usr/bin/
	# modules
	mkdir -p -m 0755 $(DESTDIR)/usr/share/perl5/
	cp -r lib/* $(DESTDIR)/usr/share/perl5/
	# docs
	mkdir -p -m 0755 $(DESTDIR)/usr/share/man/man1/
	cp man/*.1 $(DESTDIR)/usr/share/man/man1
	# cgi scripts
	mkdir -p -m 0755 $(DESTDIR)/usr/share/ubic/
	cp www/* $(DESTDIR)/usr/share/ubic/
	# configs
	cp -r etc $(DESTDIR)/

clean:
	rm -rf man
	rm -rf tfiles

.PHONY: test install clean
