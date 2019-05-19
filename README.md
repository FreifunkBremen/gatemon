# Gatemon

Projekt, um die Gateway-Server eines [Freifunk](https://freifunk.net)-Mesh-Netzwerks
auf Ausfaelle zu ueberwachen.

Das Programm laeuft regelmaessig und ueberprueft, ob die Internet-Verbindung moeglich
ist und DNS und NTP funktioniert.

Die Ergebnisse werden auf einen Webserver, auf dem [gatemon-html](https://github.com/FreifunkBremen/gatemon-html)
laeuft, welches diese dann anzeigt.

## Abhaengigkeiten

Das Programm muss auf einem Rechner laufen, welcher als normaler Teilnehmer
im Freifunk-Netz haengt.

Ausserdem sollte er NTP-synchronisiert sein, damit er eine akkurate Zeit hat, da
der gatemon-html-Server die Ergebnisse ansonsten ablehnt.

Danach braucht du einen geheimen Schluessel, damit dein Gatemon Daten an den zentralen
Server senden darf.

Diesen bekommst du zur Zeit von genofire, jplitza, mortzu oder ollibaba -
einfach im Chat fragen.

## Installation (als root)

Anleitung, wie man einen gatemon auf einem Raspberry Pi installiert, insbesondere
die Netzwerkkonfiguration, findest du im [Wiki](https://wiki.bremen.freifunk.net/Anleitungen/Gatemon-mit-Raspberry-Pi-installieren).

```
apt-get install monitoring-plugins-basic monitoring-plugins-standard dnsutils git make gcc curl
git clone https://github.com/FreifunkBremen/gatemon /opt/gatemon
cd /opt/gatemon
make libpacketmark.so
cp gatemon.cfg /etc/
cp gatemon.cron /etc/cron.d/gatemon
```

Danach musst du /etc/gatemon.cfg bearbeite:
- setze API_TOKEN auf den geheimen Schluessel, den du bekommen hast
- benenne mit GATEMON_NAME kurz deinen gatemon (bleibe unter 20 Zeichen)
- set GATEMON_PROVIDER to the name or short description of your Internet provider
- set NETWORK_DEVICE to your freifunk interface (i.e. eth0)
- leave the other entries unchanged, or ask the admin of your gatemon-html server for correct settings
