#! /usr/bin/env bash

# Exit on error
set -e

# Set path to a save default
PATH="/bin:/usr/bin:/sbin:/usr/sbin"

# Initialize variables
SITE_CONFIG_URL='https://raw.githubusercontent.com/FreifunkBremen/gluon-site-ffhb/master/domains/ffhb_batv15.conf'

NETWORK_DEVICE='ffhb-mesh'
declare -a VPN_NUMBER

# Include config if exists
if [[ -e /etc/gatemon.cfg ]]; then
    . /etc/gatemon.cfg
fi

# Fetch site config
SITE_CONFIG_CONTENT=$(curl --max-time 5 --header 'Cache-Control: no-cache' --silent --show-error "$SITE_CONFIG_URL")
if [[ -z "$SITE_CONFIG_CONTENT" ]]; then
    echo 'Failed to download site.conf!' >&2
    exit 1
fi

# Get VPN server numbers
readarray -t VPN_NUMBER <<< "$(grep -Po '\s+vpn(0)?\K.+(?=\s+=\s+{)' <<<"$SITE_CONFIG_CONTENT")"

# Extract network addresses
NETWORK4="$(grep --perl-regexp --only-matching "\s+prefix4\s+=\s+'\K.+(?=',)" <<<"$SITE_CONFIG_CONTENT")"
NETWORK6="$(grep --perl-regexp --only-matching "\s+prefix6\s+=\s+'\K.+(?=',)" <<<"$SITE_CONFIG_CONTENT")"

# Extract network base addresses
NETWORK4_BASE="$(grep --perl-regexp --only-matching "\s+prefix4\s+=\s+'\K.+\.(?=\d/\d+',)" <<<"$SITE_CONFIG_CONTENT")"
NETWORK6_BASE="$(grep --perl-regexp --only-matching "\s+prefix6\s+=\s+'\K.+(?=/\d+',)" <<<"$SITE_CONFIG_CONTENT")"

if [[ -z "$NETWORK4_BASE" ]] || \
   [[ -z "$NETWORK6_BASE" ]]; then
    echo "Failed to extract network base addresses from site.conf (${#SITE_CONFIG_CONTENT} bytes)!" >&2
    exit 1
fi

for GATE in $(seq "${VPN_NUMBER[0]}" "${VPN_NUMBER[-1]}"); do
    if [[ -z "$(ip -4 route list "$NETWORK4" table $(( 100 + GATE )) 2>/dev/null)" ]]; then
        # Add network device route to routing table
        ip route add "$NETWORK4" dev "$NETWORK_DEVICE" table $(( 100 + GATE ))
        # Add default route to routing table
        ip route add default via "${NETWORK4_BASE}${GATE}" dev "$NETWORK_DEVICE" table $(( 100 + GATE ))
        # Add firewall mark for routing table
        ip rule add fwmark "$GATE" table $(( 100 + GATE ))
    fi

    if [[ -z "$(ip -6 route list "$NETWORK6" table $(( 100 + GATE )) 2>/dev/null)" ]]; then
        # Add network device route to routing table
        ip -6 route add "$NETWORK6" dev "$NETWORK_DEVICE" table $(( 100 + GATE ))
        # Add default route to routing table
        ip -6 route add default via "${NETWORK6_BASE}${GATE}" dev "$NETWORK_DEVICE" table $(( 100 + GATE ))
        # Add firewall mark for routing table
        ip -6 rule add fwmark "$GATE" table $(( 100 + GATE ))
    fi
done
