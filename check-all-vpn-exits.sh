#! /usr/bin/env bash

# Set path to a save default
PATH=/usr/lib/nagios/plugins:/bin:/usr/bin:/sbin:/usr/sbin

# Name of runfile
RUNFILE="/run/$(basename $(readlink -f $0))"

# Script finish job
function finish {
  # Remove run file
  rm -f "$RUNFILE"
}

trap finish EXIT

# Check for run file
if [ -f "$RUNFILE" ]; then
  echo 'Runfile does exists!' >&2
  exit 1
else
  touch "$RUNFILE"
fi

TARGET_FILE='/var/www/status.json'
NETWORK4_BASE='10.196.0.'
NETWORK6_BASE='2001:bf7:540::'
NETWORK_DEVICE='ffhb-mesh'
HOST_TO_FETCH='meineip.moritzrudert.de'
VPN_NUMBER=6

# Include config if exists
if [ -e /etc/check-all-vpn-exits.cfg ]; then
  . /etc/check-all-vpn-exits.cfg
fi

# Resolve host for HTTP check
IP4_TO_FETCH="$(dig +short ${HOST_TO_FETCH} A)"
IP6_TO_FETCH="$(dig +short ${HOST_TO_FETCH} AAAA)"

# Check if resolve was successful
if [ -z "$IP4_TO_FETCH" -o -z "$IP6_TO_FETCH" ]; then
  echo 'Failed to resolve hostname!' >&2
  exit 1
fi

# Generate temporary file
TMP_FILE="$(mktemp)"

echo '{"vpn-servers":[' > "$TMP_FILE"

for GATE in $(seq 1 $VPN_NUMBER); do
  ip route add $IP4_TO_FETCH via ${NETWORK4_BASE}${GATE} dev $NETWORK_DEVICE
  ip -6 route add $IP6_TO_FETCH via ${NETWORK6_BASE}${GATE} dev $NETWORK_DEVICE

  echo -n "{\"name\":\"vpn$(printf '%.2d' ${GATE}).bremen.freifunk.net\"" >> "$TMP_FILE"

  echo -n ', "ntp_ipv4":' >> "$TMP_FILE"

  if check_ntp_time -H ${NETWORK4_BASE}${GATE} >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "ntp_ipv6":' >> "$TMP_FILE"

  if check_ntp_time -H ${NETWORK6_BASE}${GATE} >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "dhcp":' >> "$TMP_FILE"

  if check_dhcp -s ${NETWORK4_BASE}${GATE} -u -i $NETWORK_DEVICE -t 30 >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "dns_ipv4":' >> "$TMP_FILE"

  if dig +time=2 +short "$HOST_TO_FETCH" A "@${NETWORK4_BASE}${GATE}" >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "dns_ipv6":' >> "$TMP_FILE"

  if dig +time=2 +short "$HOST_TO_FETCH" A "@${NETWORK6_BASE}${GATE}" >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "ipv4":' >> "$TMP_FILE"

  if curl -4 --max-time 5 --silent "http://${HOST_TO_FETCH}/" >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "ipv6":' >> "$TMP_FILE"

  if curl -6 --max-time 5 --silent "http://${HOST_TO_FETCH}/" >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  if [ $VPN_NUMBER -eq $GATE ]; then
    echo '}' >> "$TMP_FILE"
  else
    echo '},' >> "$TMP_FILE"
  fi

  ip -6 route del $IP6_TO_FETCH via ${NETWORK6_BASE}${GATE} dev $NETWORK_DEVICE
  ip route del $IP4_TO_FETCH via ${NETWORK4_BASE}${GATE} dev $NETWORK_DEVICE
done

echo "], \"lastupdated\": \"$(date --iso-8601=seconds)\"}" >> "$TMP_FILE"

# Move to target
mv "$TMP_FILE" "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
