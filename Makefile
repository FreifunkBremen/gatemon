
DEB_VERSION:=1.0-$(shell date +%Y%m%d%H%M%S -d "$(shell git show -s --format=%cD HEAD)" )-$(shell git rev-parse HEAD | cut -c -8)
BINS=check_dhcp libpacketmark.so

all: $(BINS) deb
clean:
	rm -f $(BINS) gatemon_*.deb

check_dhcp: check_dhcp.c
	$(CC) $(CFLAGS) -o $@ $+

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
	install -Dm755 check-all-vpn-exits.sh $(DESTDIR)$(PREFIX)/opt/gatemon/check-all-vpn-exits.sh
	install -Dm755 check_dhcp $(DESTDIR)$(PREFIX)/opt/gatemon/check_dhcp
	install -Dm644 check-all-vpn-exits.cfg $(DESTDIR)$(PREFIX)/etc/check-all-vpn-exits.cfg
	install -Dm644 check-all-vpn-exits.cron $(DESTDIR)$(PREFIX)/etc/cron.d/check-all-vpn-exits
	install -Dm644 check-all-vpn-exits.service $(DESTDIR)$(PREFIX)/lib/systemd/system/check-all-vpn-exits.service
	install -Dm644 check-all-vpn-exits.timer $(DESTDIR)$(PREFIX)/lib/systemd/system/check-all-vpn-exits.timer
	install -Dm755 libpacketmark/libpacketmark.so $(DESTDIR)$(PREFIX)/opt/gatemon/libpacketmark/libpacketmark.so
	install -d $(DESTDIR)$(PREFIX)/opt/gatemon/checks
	for file in checks/*; do install -m755 "$$file" $(DESTDIR)$(PREFIX)/opt/gatemon/checks/; done
