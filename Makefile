
DEB_VERSION:=1.0-$(shell date +%Y%m%d%H%M%S -d "$(shell git show -s --format=%cD HEAD)" )-$(shell git rev-parse HEAD | cut -c -8)
BINS=check_dhcp

all: $(BINS) deb
clean:
	rm -f $(BINS) gatemon_*.deb

check_dhcp: check_dhcp.c
	gcc $(CFLAGS) -o $@ $+

deb: check_dhcp Makefile
	chmod 644 check-all-vpn-exits.cron
	fpm -f -s dir -t deb -n gatemon -a native \
		--version $(DEB_VERSION) \
		--description 'Freifunk-Bremen gateway monitoring script' \
		--url 'https://github.com/FreifunkBremen/gatemon' \
		-d 'monitoring-plugins-basic | nagios-plugins-basic' \
		-d 'monitoring-plugins-standard | nagios-plugins-standard' \
		-d nagios-plugins-contrib \
		-d ndisc6 \
		-d dnsutils \
		check-all-vpn-exits.sh=/usr/lib/gatemon/check-all-vpn-exits.sh \
		check_dhcp=/usr/lib/gatemon/check_dhcp \
		check-all-vpn-exits.cfg=/etc/check-all-vpn-exits.cfg \
		check-all-vpn-exits.cron=/etc/cron.d/check-all-vpn-exits
