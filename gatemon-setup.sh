#! /usr/bin/env bash

set -e

# Set path to a save default
PATH="/bin:/usr/bin:/sbin:/usr/sbin"

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

NETWORK_DEVICE='ffhb-mesh'
HOST_TO_FETCH='meineip.moritzrudert.de'
VPN_NUMBER=6

# Include config if exists
if [[ -e /etc/gatemon.cfg ]]; then
  . /etc/gatemon.cfg
fi

SITE_CONFIG_CONTENT=$(curl --max-time 5 --header 'Cache-Control: no-cache' --silent --show-error "$SITE_CONFIG_URL")
if [[ -z "$SITE_CONFIG_CONTENT" ]]; then
  echo 'Failed to download site.conf!' >&2
  exit 1
fi

NETWORK4="$(awk -F'=' '/prefix4/ { print $2 }' <<<"$SITE_CONFIG_CONTENT" | sed -e "s/^\s*'//g" -e "s/',\s*//g")"
NETWORK6="$(awk -F'=' '/prefix6/ { print $2 }' <<<"$SITE_CONFIG_CONTENT" | sed -e "s/^\s*'//g" -e "s/',\s*//g")"

NETWORK4_BASE="$(whitespace_awk "=" '$1 == "prefix4" { gsub("^'"'"'|0*/.*$", "", $2); print $2 }' <<<"$SITE_CONFIG_CONTENT")"
NETWORK6_BASE="$(whitespace_awk "=" '$1 == "prefix6" { gsub("^'"'"'|/.*$", "", $2); print $2 }' <<<"$SITE_CONFIG_CONTENT")"

if [[ -z "$NETWORK4_BASE" ]] || [[ -z "$NETWORK6_BASE" ]]; then
  echo "Failed to extract network base addresses from site.conf (${#SITE_CONFIG_CONTENT} bytes)!" >&2
  exit 1
fi

for GATE in $(seq 1 $VPN_NUMBER); do
  if [[ -z "$(ip -4 route list $NETWORK4 table $[ 100 + $GATE ])" ]]; then
    ip route add $NETWORK4 dev $NETWORK_DEVICE table $[ 100 + $GATE ]
    ip route add default via ${NETWORK4_BASE}${GATE} dev ${NETWORK_DEVICE} table $[ 100 + $GATE ]
    ip rule add fwmark 0x$GATE table $[ 100 + $GATE ]
  fi

  if [[ -z "$(ip -6 route list $NETWORK6 table $[ 100 + $GATE ])" ]]; then
    ip -6 route add $NETWORK6 dev $NETWORK_DEVICE table $[ 100 + $GATE ]
    ip -6 route add default via ${NETWORK6_BASE}${GATE} dev ${NETWORK_DEVICE} table $[ 100 + $GATE ]
    ip -6 rule add fwmark 0x$GATE table $[ 100 + $GATE ]
  fi
done

touch /run/gatemon-nonroot.done
