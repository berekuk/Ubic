test:
	set -e; for f in `find lib -name '*.pm'`; do perl -Ilib -c $$f; done
	set -e; for f in `find bin -type f`; do perl -Ilib -c $$f; done
	prove -v t/*.t

install:
	mkdir -p $(DESTDIR)/usr/share/perl5
	cp -r lib/ $(DESTDIR)/usr/share/perl5/
	mkdir -p $(DESTDIR)/usr/
	cp bin/* $(DESTDIR)/usr/bin/
