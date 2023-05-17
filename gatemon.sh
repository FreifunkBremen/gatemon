#! /usr/bin/env bash

# Exit on error
set -e

# Set path to a save default
PATH="$(dirname "$0"):/usr/lib/gatemon/:/usr/lib/nagios/plugins:/usr/lib/monitoring-plugins:/bin:/usr/bin:/sbin:/usr/sbin"

# Initialize variables
API_URL=''
API_TOKEN=''

GATEMON_NAME=''
GATEMON_PROVIDER=''

NEXT_NODE_URL='http://node.ffhb.de'

SITE_CONFIG_URL='https://raw.githubusercontent.com/FreifunkBremen/gluon-site-ffhb/master/domains/ffhb_batv15.conf'

NETWORK_DEVICE='eth0'
HOST_TO_FETCH='google.de'

RUN_AS_ROOT=1

declare -a VPN_NUMBER

CONFIG_FILE='/etc/gatemon.cfg'

# Parse command line arguments
for ARG in "$@"; do
    if [[ "$ARG" =~ ^--config-file= ]]; then
        CONFIG_FILE="${ARG#--config-file=}"
    fi
done

# Name of runfile
RUN_FILE="/run/$(basename "$(readlink --canonicalize "$0")")"

# Include config if exists
if [[ -e "$CONFIG_FILE" ]]; then
    . "$CONFIG_FILE"
else
    echo "${CONFIG_FILE} does not exists" >&2
    exit 1
fi

# Check for run file
if [[ -f "$RUN_FILE" ]]; then
    echo 'Runfile does exist!' >&2
    exit 1
fi

# Remove run and tmp file
# on exit
function finish {
    # Remove run file
    if [[ -n "$RUN_FILE" ]]; then
        rm --force "$RUN_FILE"
    fi

    if [[ -n "$TMP_FILE" ]]; then
        rm --force "$TMP_FILE"
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

# Fetch site config
SITE_CONFIG_CONTENT=$(curl --max-time 5 --header 'Cache-Control: no-cache' --silent --show-error "$SITE_CONFIG_URL")
if [[ -z "$SITE_CONFIG_CONTENT" ]]; then
    echo 'Failed to download site.conf!' >&2
    exit 1
fi

# Get VPN server numbers
readarray -t VPN_NUMBER <<< "$(grep --perl-regexp --only-matching '\s+vpn(0)?\K.+(?=\s+=\s+{)' <<<"$SITE_CONFIG_CONTENT")"

# Extract network base addresses
NETWORK4_BASE="$(grep --perl-regexp --only-matching "\s+prefix4\s+=\s+'\K.+\.(?=\d/\d+',)" <<<"$SITE_CONFIG_CONTENT")"
NETWORK6_BASE="$(grep --perl-regexp --only-matching "\s+prefix6\s+=\s+'\K.+(?=/\d+',)" <<<"$SITE_CONFIG_CONTENT")"

if [[ -z "$NETWORK4_BASE" ]] || \
   [[ -z "$NETWORK6_BASE" ]]; then
    echo "Failed to extract network base addresses from site.conf (${#SITE_CONFIG_CONTENT} bytes)!" >&2
    exit 1
fi

# Setup routing tables if running as root
if [[ "$RUN_AS_ROOT" = '1' ]]; then
    "$(dirname "$0")/gatemon-setup.nonroot.sh"
fi

# Get node informations
NODE_INFO="$(curl --max-time 10 --silent --fail --location "${NEXT_NODE_URL}/cgi-bin/nodeinfo" || true)"

if [[ -n "$NODE_INFO" ]]; then
    NODE_HOSTNAME="$(jq --raw-output .hostname <<<"$NODE_INFO")"
    NODE_ID="$(jq --raw-output .node_id <<<"$NODE_INFO")"
else
    NODE_INFO="$(curl --max-time 10 --silent --fail --location "${NEXT_NODE_URL}/cgi-bin/status")"

    if [[ -z "$NODE_INFO" ]]; then
        echo 'Could not fetch node informations' >&2
        exit 1
    else
        NODE_HOSTNAME="$(grep '<dt>Node name</dt>' <<<"$NODE_INFO" | awk -F'</dt>' '{ print $2 }' | sed -e 's/<[^>]*>//g')"
        NODE_ID="$(grep '<dt>Primary MAC address</dt>' <<<"$NODE_INFO" | awk -F'</dt>' '{ print $2 }' | sed -e 's/<[^>]*>//g' -e 's/://g')"
    fi
fi

# Get current VPN server
CURRENT_VPN_SERVER_IP_ADDRESS="$(mtr --report-cycles 1 --report-wide --no-dns -4 "$HOST_TO_FETCH" | grep --perl-regexp '^\s+1\.\|\-\-\s+' | awk '{ print $2 }')"

# Get version
GATEMON_VERSION="$(<"$(dirname "$0")/VERSION")"

# Generate temporary file
TMP_FILE="$(mktemp --tmpdir gatemon.XXXXXXXX)"

cat >"$TMP_FILE" <<EOF
---
- uuid: ${HOSTID}
  name: ${GATEMON_NAME}
  provider: ${GATEMON_PROVIDER}
  current_vpn_server: ${CURRENT_VPN_SERVER_IP_ADDRESS}
  version: ${GATEMON_VERSION}
  node-hostname: ${NODE_HOSTNAME}
  node-id: ${NODE_ID}
  vpn-servers:
EOF

# Iterate over VPN servers
for GATE in $(seq "${VPN_NUMBER[0]}" "${VPN_NUMBER[-1]}"); do
    echo "  - name: vpn$(printf '%.2d' "$GATE").bremen.freifunk.net" >>"$TMP_FILE"

    # Run checks
    for CHECK in "$(dirname "$0")/checks"/*.sh; do
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
