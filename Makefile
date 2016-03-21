all:
	fpm -f -s dir -t deb -n gatemon -a all \
		--deb-use-file-permissions \
		--version 1.0-$(shell git show -s --format=%ct HEAD)-$(shell git rev-parse HEAD | cut -c -8) \
		--description 'Freifunk-Bremen gateway monitoring script' \
		--url 'https://github.com/FreifunkBremen/gatemon' \
		-d 'monitoring-plugins-basic | nagios-plugins-basic' \
		-d 'monitoring-plugins-standard | nagios-plugins-standard' \
		-d nagios-plugins-contrib \
		-d ndisc6 \
		-d dnsutils \
		check-all-vpn-exits.sh=/usr/bin/check-all-vpn-exits.sh \
		check-all-vpn-exits.cfg=/etc/check-all-vpn-exits.cfg \
		check-all-vpn-exits.cron=/etc/cron.d/check-all-vpn-exits

