# Gatemon

Project to monitor the gateway servers of a [freifunk](https://freifunk.net) mesh network
for outages.

The program runs regularly and checks whether the Internet connection is possible
and DNS, DHCP and NTP are working. Each over IPv4 and IPv6.

The results will be sent to a web server running [gatemon-html](https://github.com/FreifunkBremen/gatemon-html)
which then displays them.

## Dependencies

The program must run on a computer, which is a normal participant in the
in the freifunk network.

This computer must not use DHCP, because the DHCP port is used by the DHCP check.
Therefore it must have a static IPv4 address configured.

It should be NTP synchronized to have an accurate time, because
otherwise the gatemon-html server will reject the results.

After that you need a secret key to allow your gatemon to send data to the central server.

You can get it from genofire, jplitza, mortzu or ollibaba - just ask in the chat.

## Installation (as root)

A tutorial on how to install a gatemon on a Raspberry Pi, in particular
the network configuration, can be found in the [Wiki](https://wiki.bremen.freifunk.net/Anleitungen/Gatemon-mit-Raspberry-Pi-installieren).

```
apt-get install curl dnsutils gcc git jq libc6-dev make monitoring-plugins-basic monitoring-plugins-standard mtr-tiny
git clone https://github.com/FreifunkBremen/gatemon /opt/gatemon
cd /opt/gatemon
make check_dhcp
make -C libpacketmark
cp gatemon.cfg /etc/
cp gatemon.cron /etc/cron.d/gatemon
```

After that you have to edit /etc/gatemon.cfg:
- set API_TOKEN to the secret key you got
- use GATEMON_NAME to name your gatemon (stay under 20 characters)
- set GATEMON_PROVIDER to the name or short description of your Internet provider
- set NETWORK_DEVICE to your freifunk interface (i.e. eth0)
- leave the other entries unchanged, or ask the admin of your gatemon-html server for correct settings

## Update (as root)

```
cd /opt/gatemon
git pull --rebase
make check_dhcp
```
