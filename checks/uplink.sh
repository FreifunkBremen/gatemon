#! /usr/bin/env bash

# Set path to a save default
PATH="$(dirname "$0")/..:/usr/lib/gatemon:/usr/lib/nagios/plugins:/usr/lib/monitoring-plugins:/bin:/usr/bin:/sbin:/usr/sbin"

. "$(dirname "$0")/../check-all-vpn-exits.cfg"

export TIMEFORMAT="%0R"

NETWORK_DEVICE="$1"
SERVER_IP4="$2"
SERVER_IP6="$3"

if [ -z "$NETWORK_DEVICE" ]; then
  echo ''
  exit 1
elif [ -z "$SERVER_IP4" ]; then
  echo ''
  exit 1
elif [ -z "$SERVER_IP6" ]; then
  echo ''
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

cat <<EOF
    uplink:
      '0':
EOF

# IPv4
ip route add $IP4_TO_FETCH via $SERVER_IP4 dev $NETWORK_DEVICE

ELAPSED_TIME=0
STATUS_CODE=0

exec 3>&1 4>&2
ELAPSED_TIME="$( { time curl -4 --max-time 5 --silent --output /dev/null "http://${HOST_TO_FETCH}/" 1>&3 2>&4; } 2>&1)"
exec 3>&- 4>&-

if [ "$?" = 0 ]; then
  STATUS_CODE=1
fi

cat <<EOF
        ipv4: ${STATUS_CODE}
EOF

ip route del $IP4_TO_FETCH via $SERVER_IP4 dev $NETWORK_DEVICE

# IPv6
# This is a really crude hack: If the gateway that has the host route is
# unreachable on layer 2, Linux ignores the host route (if it isn't acting as a
# router) and falls back to the route of the second-longest matching prefix
# (probably the default route). In particular, it also ignores any other host
# route with higher metric. Thus, we need to insert an unreachable route to a
# network that still matches the host, but introduces minimal damage: its /127
ip -6 route add unreachable ${IP6_TO_FETCH}/127

ip -6 route add $IP6_TO_FETCH via $SERVER_IP6 dev $NETWORK_DEVICE

ELAPSED_TIME=0
STATUS_CODE=0

exec 3>&1 4>&2
ELAPSED_TIME="$( { time curl -6 --max-time 5 --silent --output /dev/null "http://${HOST_TO_FETCH}/" 1>&3 2>&4; } 2>&1)"
exec 3>&- 4>&-

if [ "$?" = 0 ]; then
  STATUS_CODE=1
fi

cat <<EOF
        ipv6: ${STATUS_CODE}
EOF

ip -6 route del $IP6_TO_FETCH via $SERVER_IP6 dev $NETWORK_DEVICE
ip -6 route del unreachable ${IP6_TO_FETCH}/127
