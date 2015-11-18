#! /usr/bin/env bash

# Set path to a save default
PATH=/usr/lib/nagios/plugins:/bin:/usr/bin:/sbin:/usr/sbin

# Name of runfile
RUN_FILE="/run/$(basename $(readlink -f $0))"

# Script finish job
function finish {
  if [ $? -eq 0 ]; then
    # Remove run file
    if [ -n "$RUN_FILE" ]; then
      rm -f "$RUN_FILE"
    fi
  fi

  if [ -n "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
  fi

  if [ -n "$IP6_ROUTER_TMP_FILE" ]; then
    rm -rf "$IP6_ROUTER_TMP_FILE"
  fi
}

trap finish EXIT

# Check for run file
if [ -f "$RUN_FILE" ]; then
  echo 'Runfile does exists!' >&2
  exit 1
else
  touch "$RUN_FILE"
fi

API_URL=''
API_TOKEN=''

MESHMON_NAME=''
MESHMON_PROVIDER=''

SITE_CONFIG_URL='https://raw.githubusercontent.com/FreifunkBremen/gluon-site-ffhb/master/site.conf'

NETWORK_DEVICE='ffhb-mesh'
HOST_TO_FETCH='meineip.moritzrudert.de'
VPN_NUMBER=6

# Include config if exists
if [ -e /etc/check-all-vpn-exits.cfg ]; then
  . /etc/check-all-vpn-exits.cfg
fi

TMP_NETWORK4_BASE="$(curl -H 'Cache-Control: no-cache' -s "$SITE_CONFIG_URL" | awk '/prefix4/{ print $3 }' | sed -e 's/[^a-zA-Z0-9.\/]//g' | awk -F/ '{ print $1 }' | sed -e 's/.$//')"
TMP_NETWORK6_BASE="$(curl -H 'Cache-Control: no-cache' -s "$SITE_CONFIG_URL" | awk '/prefix6/{ print $3 }' | sed -e 's/[^a-zA-Z0-9:\/]//g' | awk -F/ '{ print $1 }')"

if [ -n "$TMP_NETWORK4_BASE" ]; then
  NETWORK4_BASE="$TMP_NETWORK4_BASE"
fi

if [ -n "$TMP_NETWORK6_BASE" ]; then
  NETWORK6_BASE="$TMP_NETWORK6_BASE"
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

# Generate temporary file for IPv6 router check
IP6_ROUTER_TMP_FILE="$(mktemp)"

rdisc6 -r 5 -w 10000 -m "$NETWORK_DEVICE" | grep 'Recursive DNS server' | sort | sort -u | awk '{ print $5 }' > "$IP6_ROUTER_TMP_FILE"

function do_check() {
  echo -n "\"$1\":[{"

  COUNTER=0
  for HOST in $2 $3; do
    let COUNTER=COUNTER+1

    if grep -q '\.' <<<"$HOST"; then
      echo -n '"ipv4":'
    else
      echo -n '"ipv6":'
    fi

    if $4 $HOST >/dev/null; then
      echo -n '1'
    else
      echo -n '0'
    fi

    if [ $COUNTER -ne 2 ]; then
      echo -n ','
    fi
  done

  echo '}]'
}

echo "{\"uuid\":\"$(hostid)\",\"name\":\"${MESHMON_NAME}\",\"provider\":\"${MESHMON_PROVIDER}\",\"vpn-servers\":[" > "$TMP_FILE"

for GATE in $(seq 1 $VPN_NUMBER); do
  ip route add $IP4_TO_FETCH via ${NETWORK4_BASE}${GATE} dev $NETWORK_DEVICE
  ip -6 route add $IP6_TO_FETCH via ${NETWORK6_BASE}${GATE} dev $NETWORK_DEVICE

  echo "{\"name\":\"vpn$(printf '%.2d' ${GATE}).bremen.freifunk.net\"," >> "$TMP_FILE"

  do_check 'ntp' "${NETWORK4_BASE}${GATE}" "${NETWORK6_BASE}${GATE}" 'check_ntp_time -H' >> "$TMP_FILE"

  echo -n ', "addresses":[{"ipv4":' >> "$TMP_FILE"

  if check_dhcp -s ${NETWORK4_BASE}${GATE} -u -i $NETWORK_DEVICE -t 30 >/dev/null; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n ', "ipv6": ' >> "$TMP_FILE"

  if grep -Eq "^${NETWORK6_BASE}${GATE}\$" "$IP6_ROUTER_TMP_FILE"; then
    echo -n '1' >> "$TMP_FILE"
  else
    echo -n '0' >> "$TMP_FILE"
  fi

  echo -n '}],' >> "$TMP_FILE"

  do_check 'dns' "${NETWORK4_BASE}${GATE}" "${NETWORK6_BASE}${GATE}" "check_dns -H $HOST_TO_FETCH -s" >> "$TMP_FILE"

  echo -n ', "uplink":[{"ipv4":' >> "$TMP_FILE"

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

  echo '}]' >> "$TMP_FILE"

  if [ $VPN_NUMBER -eq $GATE ]; then
    echo '}' >> "$TMP_FILE"
  else
    echo '},' >> "$TMP_FILE"
  fi

  ip -6 route del $IP6_TO_FETCH via ${NETWORK6_BASE}${GATE} dev $NETWORK_DEVICE
  ip route del $IP4_TO_FETCH via ${NETWORK4_BASE}${GATE} dev $NETWORK_DEVICE
done

echo "], \"lastupdated\": \"$(date --iso-8601=seconds)\"}" >> "$TMP_FILE"

# Push to master
curl -s -X POST -d @${TMP_FILE} "${API_URL}?token=${API_TOKEN}"
