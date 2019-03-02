# Gatemon

Script to monitor the gateway servers of a [Freifunk](https://freifunk.net) mesh network for outages.

The script is executed periodically and tests Internet uplink, DNS, DHCP and NTP services (both IPv4 and IPv6) on each gateway. Results are uploaded to a webserver where [gatemon-html](https://github.com/FreifunkBremen/gatemon-html) is running, which displays the latest results of all gatemons.

## Requirements

This script needs to be run on a host which connects to a Freifunk network as a normal Client.

Gatemon hosts must not use DHCP, since the DHCP port will be used during the tests. So a static IPv4 address should be used.

Gatemon hosts should have NTP enabled to have accurate system time, since the gatemon-html server will reject any results where the timestamp is off by more than 60 seconds.

You need a secret API token from the admin of the gatemon-html server.

## Installation (as root)
Further instructions for the correct setup of the networking-stuff (at the moment in german only, WIP): [Instructions in our FreifunkBremen-Wiki](https://wiki.bremen.freifunk.net/Anleitungen/Gatemon-mit-Raspberry-Pi-installieren)

```
apt-get install monitoring-plugins-basic monitoring-plugins-standard dnsutils git make gcc curl
git clone https://github.com/FreifunkBremen/gatemon /opt/gatemon
cd /opt/gatemon
make check_dhcp
cp check-all-vpn-exits.cfg /etc/
cp check-all-vpn-exits.cron /etc/cron.d/check-all-vpn-exits
```

Then edit /etc/check-all-vpn-exits.cfg:
- set API_TOKEN to a new token received from the gatemon-html server admin
- set MESHMON_NAME to a short and descriptive name of your gatemon instance (try to stay below 20 characters)
- set MESHMON_PROVIDER to the name or short description of your Internet provider
- set NETWORK_DEVICE to your freifunk interface (i.e. eth0)
- leave the other entries unchanged, or ask the admin of your gatemon-html server for correct settings

## Update (as root)

```
cd /opt/gatemon
git pull --rebase
make check_dhcp
```
