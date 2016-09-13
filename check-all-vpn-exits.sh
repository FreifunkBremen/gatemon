#! /usr/bin/env bash

# Set path to a save default
PATH="$(dirname "$0"):/usr/lib/gatemon/:/usr/lib/nagios/plugins:/bin:/usr/bin:/sbin:/usr/sbin"

whitespace_awk() {
    SEP="$1"
    shift
    awk -v 'RS=\n[\t ]*' -F' +'"$SEP"' +' "$@"
}

check_ipv6() {
  if whitespace_awk ':' '$1 == "Recursive DNS server" && $2 == "'"$1"'" { exit 1 }' <<<"$RDISC_OUTPUT"; then
    return 1
  else
    return 0
  fi
}

# Name of runfile
RUN_FILE="/run/$(basename $(readlink -f $0))"

# Check for run file
if [[ -f "$RUN_FILE" ]]; then
  echo 'Runfile does exist!' >&2
  exit 1
fi

# Script finish job
function finish {
  # Remove run file
  if [[ -n "$RUN_FILE" ]]; then
    rm -f "$RUN_FILE"
  fi

  if [[ -n "$TMP_FILE" ]]; then
    rm -f "$TMP_FILE"
  fi
}

trap finish EXIT
touch "$RUN_FILE"

API_URL=''
API_TOKEN=''

MESHMON_NAME=''
MESHMON_PROVIDER=''

SITE_CONFIG_URL='https://raw.githubusercontent.com/FreifunkBremen/gluon-site-ffhb/master/site.conf'

NETWORK_DEVICE='ffhb-mesh'
HOST_TO_FETCH='meineip.moritzrudert.de'
VPN_NUMBER=6

# Include config if exists
if [[ -e /etc/check-all-vpn-exits.cfg ]]; then
  . /etc/check-all-vpn-exits.cfg
fi

# Sleep some random time
# max 60s
sleep $[ ( $RANDOM % 60 ) + 1 ]s

# Try to find some unique host identification
for file in /etc/machine-id /var/lib/dbus/machine-id /etc/hostid; do
  if [[ -r "$file" ]]; then
    HOSTID="$(<"$file")"
    break
  fi
done
if [[ -z "$HOSTID" ]]; then
  echo 'Could not determine unique host ID.' >&2
  exit 1
fi

SITE_CONFIG_CONTENT=$(curl --max-time 5 -H 'Cache-Control: no-cache' -s -S "$SITE_CONFIG_URL")
if [[ -z "$SITE_CONFIG_CONTENT" ]]; then
  echo 'Failed to download site.conf!' >&2
  exit 1
fi

NETWORK4_BASE="$(whitespace_awk "=" '$1 == "prefix4" { gsub("^'"'"'|0*/.*$", "", $2); print $2 }' <<<"$SITE_CONFIG_CONTENT")"
NETWORK6_BASE="$(whitespace_awk "=" '$1 == "prefix6" { gsub("^'"'"'|/.*$", "", $2); print $2 }' <<<"$SITE_CONFIG_CONTENT")"
if [[ -z "$NETWORK4_BASE" ]] || [[ -z "$NETWORK6_BASE" ]]; then
  echo "Failed to extract network base addresses from site.conf (${#SITE_CONFIG_CONTENT} bytes)!" >&2
  exit 1
fi

# Resolve host for HTTP check
IP4_TO_FETCH="$(dig +short ${HOST_TO_FETCH} A | tail -n1)"
IP6_TO_FETCH="$(dig +short ${HOST_TO_FETCH} AAAA | tail -n1)"

# Check if resolve was successful
if [[ -z "$IP4_TO_FETCH" ]] || [[ -z "$IP6_TO_FETCH" ]]; then
  echo 'Failed to resolve hostname!' >&2
  exit 1
fi

# Generate temporary file
TMP_FILE="$(mktemp)"

function do_check() {
  echo -n "\"$1\":[{"

  COUNTER=0
  for HOST in $2 $3; do
    let COUNTER=COUNTER+1
    CHECK_COMMAND="$4"

    if [[ "${HOST/./}" != "$HOST" ]]; then
      echo -n '"ipv4":'
    else
      echo -n '"ipv6":'

      if [[ -n "$5" ]]; then
        CHECK_COMMAND="$5"
      fi
    fi

    if $CHECK_COMMAND $HOST >/dev/null; then
      echo -n '1'
    else
      echo -n '0'
    fi

    if [[ $COUNTER -ne 2 ]]; then
      echo -n ','
    fi
  done

  echo '}]'
}

RDISC_OUTPUT="$(LC_ALL=C rdisc6 -r 5 -w 10000 -m "$NETWORK_DEVICE")"

echo "{\"uuid\":\"$HOSTID\",\"name\":\"${MESHMON_NAME}\",\"provider\":\"${MESHMON_PROVIDER}\",\"vpn-servers\":[" > "$TMP_FILE"

# This is a really crude hack: If the gateway that has the host route is
# unreachable on layer 2, Linux ignores the host route (if it isn't acting as a
# router) and falls back to the route of the second-longest matching prefix
# (probably the default route). In particular, it also ignores any other host
# route with higher metric. Thus, we need to insert an unreachable route to a
# network that still matches the host, but introduces minimal damage: its /127
ip -6 route add unreachable ${IP6_TO_FETCH}/127

for GATE in $(seq 1 $VPN_NUMBER); do
  ip route add $IP4_TO_FETCH via ${NETWORK4_BASE}${GATE} dev $NETWORK_DEVICE
  ip -6 route add $IP6_TO_FETCH via ${NETWORK6_BASE}${GATE} dev $NETWORK_DEVICE

  echo "{\"name\":\"vpn$(printf '%.2d' ${GATE}).bremen.freifunk.net\"," >> "$TMP_FILE"

  do_check 'ntp' "${NETWORK4_BASE}${GATE}" "${NETWORK6_BASE}${GATE}" 'check_ntp_time -H' >> "$TMP_FILE"

  echo ', ' >> "$TMP_FILE"

  do_check 'addresses' "${NETWORK4_BASE}${GATE}" "${NETWORK6_BASE}${GATE}" "check_dhcp -t 30 $NETWORK_DEVICE" "check_ipv6" >> "$TMP_FILE"

  echo ', ' >> "$TMP_FILE"

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

  if [[ $VPN_NUMBER -eq $GATE ]]; then
    echo '}' >> "$TMP_FILE"
  else
    echo '},' >> "$TMP_FILE"
  fi

  ip -6 route del $IP6_TO_FETCH via ${NETWORK6_BASE}${GATE} dev $NETWORK_DEVICE
  ip route del $IP4_TO_FETCH via ${NETWORK4_BASE}${GATE} dev $NETWORK_DEVICE
done

ip -6 route del unreachable ${IP6_TO_FETCH}/127

echo "], \"lastupdated\": \"$(date --iso-8601=seconds)\"}" >> "$TMP_FILE"

# Push to master
curl --max-time 5 -s -S -X POST -d @${TMP_FILE} "${API_URL}?token=${API_TOKEN}" >&2
