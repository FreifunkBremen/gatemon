#! /usr/bin/env bash

# Set path to a save default
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

cat <<EOF
    dns:
      '0':
EOF

# IPv4
ELAPSED_TIME=0
STATUS_CODE=0

exec 3>/dev/null 4>/dev/null
ELAPSED_TIME="$( { time check_dns -H "$HOST_TO_FETCH" -s "$SERVER_IP4" 1>&3 2>&4; } 2>&1)"
exec 3>&- 4>&-

if [ "$?" = 0 ]; then
  STATUS_CODE=1
fi

cat <<EOF
        ipv4: ${STATUS_CODE}
EOF

# IPv6
ELAPSED_TIME=0
STATUS_CODE=0

exec 3>/dev/null 4>/dev/null
ELAPSED_TIME="$( { time check_dns -H "$HOST_TO_FETCH" -s "$SERVER_IP6" 1>&3 2>&4; } 2>&1)"
exec 3>&- 4>&-

if [ "$?" = 0 ]; then
  STATUS_CODE=1
fi

cat <<EOF
        ipv6: ${STATUS_CODE}
EOF
