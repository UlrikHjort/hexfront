# Hexfront build, test and install.
#
#   make                 build the game (bin/hexfront)
#   make test            build and run the headless self-test
#   make balance         AI-vs-AI balance report (ROUNDS=20 by default)
#   make render          headless PNG render tools
#   make screenshots     regenerate docs/screenshots (needs ImageMagick)
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

.PHONY: all test balance render screenshots data install uninstall clean

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

SHOTS = docs/screenshots
SCN   = data/scenarios

screenshots: render
	mkdir -p $(SHOTS)
	./bin/render_png $(SCN)/ww2_normandy.scn $(SHOTS)/raw.png sil,turns=3
	convert $(SHOTS)/raw.png -resize 1000x -colors 256 -strip PNG8:$(SHOTS)/normandy.png
	./bin/render_png $(SCN)/ww2_bastogne.scn $(SHOTS)/raw.png snow,turns=6
	convert $(SHOTS)/raw.png -resize 1000x -colors 256 -strip PNG8:$(SHOTS)/bastogne.png
	./bin/render_png $(SCN)/acw_gettysburg.scn $(SHOTS)/raw.png sil,rain,turns=2
	convert $(SHOTS)/raw.png -resize 1000x -colors 256 -strip PNG8:$(SHOTS)/gettysburg.png
	./bin/render_png $(SCN)/nap_waterloo.scn $(SHOTS)/raw.png turns=2
	convert $(SHOTS)/raw.png -resize 1000x -colors 256 -strip PNG8:$(SHOTS)/waterloo.png
	./bin/render_png $(SCN)/ww2_bastogne.scn $(SHOTS)/raw.png supply,turns=8
	convert $(SHOTS)/raw.png -crop 900x500+150+250 +repage -colors 256 -strip PNG8:$(SHOTS)/supply.png
	rm -f $(SHOTS)/raw.png

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
