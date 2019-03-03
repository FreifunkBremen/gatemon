
DEB_VERSION:=1.0-$(shell date +%Y%m%d%H%M%S -d "$(shell git show -s --format=%cD HEAD)" )-$(shell git rev-parse HEAD | cut -c -8)
BINS=check_dhcp libpacketmark.so

all: $(BINS) deb
clean:
	rm -f $(BINS) gatemon_*.deb

check_dhcp: check_dhcp.c
	$(CC) $(CFLAGS) -o $@ $+

libpacketmark.so:
	mkdir -p libpacketmark
	wget -q -O libpacketmark/libpacketmark.c -c https://github.com/freifunk-gluon/packages/raw/master/libs/libpacketmark/src/libpacketmark.c
	wget -q -O libpacketmark/Makefile -c https://github.com/freifunk-gluon/packages/raw/master/libs/libpacketmark/src/Makefile
	make -C libpacketmark

archlinux: check_dhcp Makefile
	chmod 644 check-all-vpn-exits.cron
	fpm -f -s dir -t pacman -n gatemon -a native \
		--version $(DEB_VERSION) \
		--description 'Freifunk-Bremen gateway monitoring script' \
		--url 'https://github.com/FreifunkBremen/gatemon' \
		-d curl \
		-d monitoring-plugins \
		-d bind-tools \
		check-all-vpn-exits.sh=/opt/gatemon/check-all-vpn-exits.sh \
		check_dhcp=/opt/gatemon/check_dhcp \
		check-all-vpn-exits.cfg=/etc/check-all-vpn-exits.cfg \
		check-all-vpn-exits.cron=/etc/cron.d/check-all-vpn-exits \
		check-all-vpn-exits.service=/lib/systemd/system/check-all-vpn-exits.service \
		check-all-vpn-exits.timer=/lib/systemd/system/check-all-vpn-exits.timer \
		libpacketmark/libpacketmark.so=/opt/gatemon/libpacketmark/libpacketmark.so \
		checks/addresses-nonroot.sh=/opt/gatemon/checks/addresses-nonroot.sh \
		checks/addresses-root.sh=/opt/gatemon/checks/addresses-root.sh \
		checks/dns-nonroot.sh=/opt/gatemon/checks/dns-nonroot.sh \
		checks/dns-root.sh=/opt/gatemon/checks/dns-root.sh \
		checks/ntp-nonroot.sh=/opt/gatemon/checks/ntp-nonroot.sh \
		checks/ntp-root.sh=/opt/gatemon/checks/ntp-root.sh \
		checks/uplink-nonroot.sh=/opt/gatemon/checks/uplink-nonroot.sh \
		checks/uplink-root.sh=/opt/gatemon/checks/uplink-root.sh

deb: check_dhcp Makefile
	chmod 644 check-all-vpn-exits.cron
	fpm -f -s dir -t deb -n gatemon -a native \
		--version $(DEB_VERSION) \
		--description 'Freifunk-Bremen gateway monitoring script' \
		--url 'https://github.com/FreifunkBremen/gatemon' \
		-d 'monitoring-plugins-basic | nagios-plugins-basic' \
		-d 'monitoring-plugins-standard | nagios-plugins-standard' \
		-d dnsutils \
		check-all-vpn-exits.sh=/opt/gatemon/check-all-vpn-exits.sh \
		check_dhcp=/opt/gatemon/check_dhcp \
		check-all-vpn-exits.cfg=/etc/check-all-vpn-exits.cfg \
		check-all-vpn-exits.cron=/etc/cron.d/check-all-vpn-exits \
		check-all-vpn-exits.service=/lib/systemd/system/check-all-vpn-exits.service \
		check-all-vpn-exits.timer=/lib/systemd/system/check-all-vpn-exits.timer \
		libpacketmark/libpacketmark.so=/opt/gatemon/libpacketmark/libpacketmark.so \
		checks/addresses-nonroot.sh=/opt/gatemon/checks/addresses-nonroot.sh \
		checks/addresses-root.sh=/opt/gatemon/checks/addresses-root.sh \
		checks/dns-nonroot.sh=/opt/gatemon/checks/dns-nonroot.sh \
		checks/dns-root.sh=/opt/gatemon/checks/dns-root.sh \
		checks/ntp-nonroot.sh=/opt/gatemon/checks/ntp-nonroot.sh \
		checks/ntp-root.sh=/opt/gatemon/checks/ntp-root.sh \
		checks/uplink-nonroot.sh=/opt/gatemon/checks/uplink-nonroot.sh \
		checks/uplink-root.sh=/opt/gatemon/checks/uplink-root.sh

install:
	install -Dm755 check-all-vpn-exits.sh $(DESTDIR)$(PREFIX)/opt/gatemon/check-all-vpn-exits.sh
	install -Dm755 check_dhcp $(DESTDIR)$(PREFIX)/opt/gatemon/check_dhcp
	install -Dm644 check-all-vpn-exits.cfg $(DESTDIR)$(PREFIX)/etc/check-all-vpn-exits.cfg
	install -Dm644 check-all-vpn-exits.cron $(DESTDIR)$(PREFIX)/etc/cron.d/check-all-vpn-exits
	install -Dm644 check-all-vpn-exits.service $(DESTDIR)$(PREFIX)/lib/systemd/system/check-all-vpn-exits.service
	install -Dm644 check-all-vpn-exits.timer $(DESTDIR)$(PREFIX)/lib/systemd/system/check-all-vpn-exits.timer
	install -Dm755 libpacketmark/libpacketmark.so $(DESTDIR)$(PREFIX)/opt/gatemon/libpacketmark/libpacketmark.so
	install -d $(DESTDIR)$(PREFIX)/opt/gatemon/checks
	for file in checks/*; do install -m755 "$$file" $(DESTDIR)$(PREFIX)/opt/gatemon/checks/; done
