#! /usr/bin/env bash

# Set path to a save default
# Set path to a save default
PATH="$(dirname "$0")/..:/usr/lib/gatemon:/usr/lib/nagios/plugins:/usr/lib/monitoring-plugins:/bin:/usr/bin:/sbin:/usr/sbin"

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
TMP_FILE="$(mktemp)"

# Delete lockfile after completion
cleanup() {
  if [ -n "$TMP_FILE" -a -f "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
  fi
}
trap cleanup EXIT

if [[ -z "$NETWORK_DEVICE" ]] || [[ -z "$SERVER_IP4" ]] || [[ -z "$SERVER_IP6" ]]; then
  echo "$0 <device> <ipv4> <ipv6>" >&2
  exit 1
fi

cat <<EOF
    ntp:
      '0':
EOF

# IPv4
ERROR_MESSAGE=''
ELAPSED_TIME=0
STATUS_CODE=0

exec 3>"$TMP_FILE" 4>/dev/null
ELAPSED_TIME="$( { time check_ntp_time -H "$SERVER_IP4" 1>&3 2>&4; } 2>&1)"
if [[ "$?" = 0 ]]; then
  STATUS_CODE=1
else
  ERROR_MESSAGE="$(head -n1 <"$TMP_FILE")"
fi
exec 3>&- 4>&-

cat <<EOF
        ipv4:
          status: ${STATUS_CODE}
          time: ${ELAPSED_TIME}
          error-message: '${ERROR_MESSAGE}'
EOF

rm -f "$TMP_FILE"

# IPv6
ERROR_MESSAGE=''
ELAPSED_TIME=0
STATUS_CODE=0

exec 3>"$TMP_FILE" 4>/dev/null
ELAPSED_TIME="$( { time check_ntp_time -H "$SERVER_IP6" 1>&3 2>&4; } 2>&1)"
if [[ "$?" = 0 ]]; then
  STATUS_CODE=1
else
  ERROR_MESSAGE="$(head -n1 <"$TMP_FILE")"
fi
exec 3>&- 4>&-

cat <<EOF
        ipv6:
          status: ${STATUS_CODE}
          time: ${ELAPSED_TIME}
          error-message: '${ERROR_MESSAGE}'
EOF
