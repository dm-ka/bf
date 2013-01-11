include Makefile.config

all:
	./compile

.PHONY: install

install:
	install -m 755 -d $(PREFIX) $(PREFIX)/bin
	install -m 755 _build/src/bf.native $(PREFIX)/bin
	install -m 755 tools/ssh-copy-id $(PREFIX)/bin
	install -m 755 tools/make-autologin $(PREFIX)/bin

.PHONY: uninstall
uninstall:
	rm -f $(PREFIX)/bin/bf

.PHONY: clean
clean:
	rm -f _build

.PHONY: distclean
distclean: clean
	rm -f *~ Makefile.config
	rm -rf _build
