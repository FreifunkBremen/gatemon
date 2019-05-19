
DEB_VERSION:=1.0-$(shell date +%Y%m%d%H%M%S -d "$(shell git show -s --format=%cD HEAD)" )-$(shell git rev-parse HEAD | cut -c -8)
BINS=libpacketmark.so

all: $(BINS) deb
clean:
	rm -f $(BINS) gatemon_*.deb

libpacketmark.so:
	mkdir -p libpacketmark
	curl --location --continue-at - --silent --show-error --output libpacketmark/libpacketmark.c https://github.com/freifunk-gluon/packages/raw/master/libs/libpacketmark/src/libpacketmark.c
	curl --location --continue-at - --silent --show-error --output libpacketmark/Makefile https://github.com/freifunk-gluon/packages/raw/master/libs/libpacketmark/src/Makefile
	make -C libpacketmark

archlinux: $(BINS)
	makepkg -s

deb: $(BINS)
	checkinstall -D \
		--default \
		--backup=no \
		--fstrans=yes \
		--install=no \
		--pkgname=gatemon \
		--maintainer=mortzu@gmx.de \
		--nodoc \
		--pkglicense=custom \
		--requires="curl,dnsutils,monitoring-plugins-basic,monitoring-plugins-standard"

install: $(BINS)
	install -d $(DESTDIR)$(PREFIX)/opt
	install -d $(DESTDIR)$(PREFIX)/opt/gatemon
	install -Dm755 gatemon.sh $(DESTDIR)$(PREFIX)/opt/gatemon/gatemon.sh
	install -Dm644 VERSION $(DESTDIR)$(PREFIX)/opt/gatemon/VERSION
	install -Dm644 gatemon.cfg $(DESTDIR)$(PREFIX)/etc/gatemon.cfg
	install -Dm644 gatemon.cron $(DESTDIR)$(PREFIX)/etc/cron.d/gatemon
	install -Dm644 gatemon.root.service $(DESTDIR)$(PREFIX)/lib/systemd/system/gatemon.root.service
	install -Dm644 gatemon.nonroot.service $(DESTDIR)$(PREFIX)/lib/systemd/system/gatemon.nonroot.service
	install -Dm644 gatemon-setup.nonroot.service $(DESTDIR)$(PREFIX)/lib/systemd/system/gatemon-setup.nonroot.service
	ln -sf /lib/systemd/system/gatemon.root.service $(DESTDIR)$(PREFIX)/lib/systemd/system/gatemon.service
	install -Dm644 gatemon.timer $(DESTDIR)$(PREFIX)/lib/systemd/system/gatemon.timer
	install -Dm755 libpacketmark/libpacketmark.so $(DESTDIR)$(PREFIX)/opt/gatemon/libpacketmark/libpacketmark.so
	install -d $(DESTDIR)$(PREFIX)/opt/gatemon/checks
	for file in checks/*; do install -m755 "$$file" $(DESTDIR)$(PREFIX)/opt/gatemon/checks/; done
