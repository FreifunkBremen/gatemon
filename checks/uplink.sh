#! /usr/bin/env bash

# Set path to a save default
PATH="$(dirname "$0")/..:/usr/lib/gatemon:/usr/lib/nagios/plugins:/usr/lib/monitoring-plugins:/bin:/usr/bin:/sbin:/usr/sbin"

export LD_PRELOAD="$(dirname "$0")/../libpacketmark/libpacketmark.so"

# Include config if exists
if [[ -e /etc/gatemon.cfg ]]; then
    . /etc/gatemon.cfg
else
    echo '/etc/gatemon.cfg does not exists' >&2
    exit 1
fi

export TIMEFORMAT="%2R"

NETWORK_DEVICE="$1"
SERVER_IP4="$2"
SERVER_IP6="$3"
GATE="$4"
TMP_FILE="$(mktemp)"

# Delete lockfile after completion
cleanup() {
  if [[ -n "$TMP_FILE" ]] && \
     [[ -f "$TMP_FILE" ]]; then
      rm --force "$TMP_FILE"
  fi
}
trap cleanup EXIT

if [[ -z "$NETWORK_DEVICE" ]] || \
   [[ -z "$SERVER_IP4" ]] || \
   [[ -z "$SERVER_IP6" ]] || \
   [[ -z "$GATE" ]]; then
  echo "$0 <device> <ipv4> <ipv6> <gatenum>" >&2
  exit 1
fi

export LIBPACKETMARK_MARK=$GATE

cat <<EOF
    uplink:
      '0':
EOF

# IPv4
ERROR_MESSAGE=''
ELAPSED_TIME=0
STATUS_CODE=0

exec 3>&1 4>"$TMP_FILE"
ELAPSED_TIME="$( { time curl --ipv4 --max-time 5 --show-error --silent --output /dev/null "http://${HOST_TO_FETCH}/" 1>&3 2>&4; } 2>&1)"
if [[ "$?" = 0 ]]; then
    STATUS_CODE=1
else
    ERROR_MESSAGE="$(head --lines=1 <"$TMP_FILE")"
fi
exec 3>&- 4>&-

cat <<EOF
        ipv4:
          status: ${STATUS_CODE}
          time: ${ELAPSED_TIME}
          error-message: '${ERROR_MESSAGE}'
EOF

rm --force "$TMP_FILE"

# IPv6
ERROR_MESSAGE=''
ELAPSED_TIME=0
STATUS_CODE=0

exec 3>&1 4>"$TMP_FILE"
ELAPSED_TIME="$( { time curl --ipv6 --max-time 5 --show-error --silent --output /dev/null "http://${HOST_TO_FETCH}/" 1>&3 2>&4; } 2>&1)"
if [[ "$?" = 0 ]]; then
    STATUS_CODE=1
else
    ERROR_MESSAGE="$(head --lines=1 <"$TMP_FILE")"
fi
exec 3>&- 4>&-

cat <<EOF
        ipv6:
          status: ${STATUS_CODE}
          time: ${ELAPSED_TIME}
          error-message: '${ERROR_MESSAGE}'
EOF
