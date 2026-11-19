# Hexfront build, test and install.
#
#   make                 build the game (bin/hexfront)
#   make test            build and run the headless self-test
#   make balance         AI-vs-AI balance report (ROUNDS=20 by default)
#   make render          headless PNG render tools
#   make data            regenerate scenarios and sounds (needs python3)
#   make install         install to $(PREFIX) (default /usr/local)
#   make uninstall
#   make clean

PREFIX   ?= /usr/local
DESTDIR  ?=
GPRBUILD ?= gprbuild
ROUNDS   ?= 20

BINDIR   = $(DESTDIR)$(PREFIX)/bin
SHAREDIR = $(DESTDIR)$(PREFIX)/share/hexfront
APPDIR   = $(DESTDIR)$(PREFIX)/share/applications
ICONDIR  = $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps

.PHONY: all test balance render data install uninstall clean

all:
	$(GPRBUILD) -p -P hexfront.gpr

test:
	$(GPRBUILD) -p -P selftest.gpr
	./bin/selftest

balance:
	$(GPRBUILD) -p -P selftest.gpr
	./bin/selftest $(ROUNDS)

render:
	$(GPRBUILD) -p -P render.gpr

data:
	python3 tools/gen_scenarios.py
	python3 tools/gen_sounds.py

install: all
	install -d $(BINDIR) $(SHAREDIR) $(APPDIR) $(ICONDIR)
	install -m 755 bin/hexfront $(BINDIR)/hexfront
	cp -r data/eras data/scenarios data/campaigns data/sounds data/icons $(SHAREDIR)/
	install -m 644 packaging/hexfront.desktop $(APPDIR)/hexfront.desktop
	install -m 644 data/icons/hexfront.svg $(ICONDIR)/hexfront.svg

uninstall:
	rm -f $(BINDIR)/hexfront $(APPDIR)/hexfront.desktop $(ICONDIR)/hexfront.svg
	rm -rf $(SHAREDIR)

clean:
	rm -rf obj bin
