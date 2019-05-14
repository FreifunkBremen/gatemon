#! /usr/bin/env bash

set -e

# Set path to a save default
PATH="$(dirname "$0"):/usr/lib/gatemon/:/usr/lib/nagios/plugins:/usr/lib/monitoring-plugins:/bin:/usr/bin:/sbin:/usr/sbin"

whitespace_awk() {
  SEP="$1"
  shift
  awk -v 'RS=\n[\t ]*' -F' +'"$SEP"' +' "$@"
}

API_URL=''
API_TOKEN=''

MESHMON_NAME=''
MESHMON_PROVIDER=''

SITE_CONFIG_URL='https://raw.githubusercontent.com/FreifunkBremen/gluon-site-ffhb/master/site.conf'

NETWORK_DEVICE='eth0'
HOST_TO_FETCH='google.de'
VPN_NUMBER=6

RUN_AS_ROOT=1

# Name of runfile
RUN_FILE="/run/$(basename $(readlink -f $0))"

# Include config if exists
if [[ -e /etc/gatemon.cfg ]]; then
  . /etc/gatemon.cfg
else
  echo '/etc/gatemon.cfg does not exists' >&2
  exit 1
fi

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

# Sleep some random time
# max 60s
sleep $(( ( RANDOM % 60 ) + 1 ))s

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

SITE_CONFIG_CONTENT=$(curl --max-time 5 --header 'Cache-Control: no-cache' --silent --show-error "$SITE_CONFIG_URL")
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

if [[ "$RUN_AS_ROOT" = '1' ]]; then
  CHECK_SUFFIX='-root'

  $(dirname "$0")/gatemon-setup.nonroot.sh
else
  CHECK_SUFFIX='-nonroot'
fi

# Get version
GATEMON_VERSION="$(<$(dirname "$0")/VERSION)"

# Generate temporary file
TMP_FILE="$(mktemp)"

cat >"$TMP_FILE" <<EOF
---
- uuid: ${HOSTID}
  name: ${MESHMON_NAME}
  provider: ${MESHMON_PROVIDER}
  version: ${GATEMON_VERSION}
  vpn-servers:
EOF

for GATE in $(seq 1 $VPN_NUMBER); do
  echo "  - name: vpn$(printf '%.2d' ${GATE}).bremen.freifunk.net" >>"$TMP_FILE"

  for CHECK in $(dirname "$0")/checks/*${CHECK_SUFFIX}.sh; do
    "$CHECK" "$NETWORK_DEVICE" "${NETWORK4_BASE}${GATE}" "${NETWORK6_BASE}${GATE}" "$GATE" >> "$TMP_FILE"
  done
done

cat >>"$TMP_FILE" <<EOF
  lastupdated: "$(date --iso-8601=seconds)"
EOF

# Push to master
if ! curl --max-time 5 --show-error --silent --request POST --data-binary @"${TMP_FILE}" "${API_URL}?token=${API_TOKEN}" >&2; then
  echo "Pushing result to server failed." >&2
fi
