#!/usr/bin/env bash

source /usr/local/etc/brocade-tools.conf

DEVICE="$1"

if [ -z "$DEVICE" ]; then
	echo "Provide a device!" >&2
	exit 31
fi
if [ -z "$COMMUNITY" ]; then
	echo "Edit /usr/local/etc/brocade-tools.conf and add your community string." >&2
	echo "Like this:" >&2
	echo "COMMUNITY=\"public\"" >&2
	exit 32
fi

LAG_PORTS_OID=".1.3.6.1.4.1.1991.1.1.3.33.1.1.1.4"
PORT_DESC_OID=".1.3.6.1.2.1.31.1.1.1.1"
PORT_LACP_STATUS_OID=".1.3.6.1.4.1.1991.1.1.3.33.3.1.1.3"
LAG_ID_OID=".1.3.6.1.4.1.1991.1.1.3.33.1.1.1.12"

function log {
	echo "$1" >&2
}

RETURN=0
MORE_INFO=""
PROBLEM_CHILD=""

log "Discovering LAGs..."
#We need -Ox so that we get a hex string.
#We need -On so that we can perform surgery on the OIDs later.
#Then we grep out any LAGs that have zero ports.
LAGS="$(snmpwalk -Ox -On -c $COMMUNITY -v 1 $DEVICE $LAG_PORTS_OID | grep -v '""' )"
LAG_COUNT="$(echo $LAGS | wc -l)"

while read -r LAG; do
	if [ -z "$LAG" ]; then
		LAG_COUNT="$(echo "$LAG_COUNT-1" | bc)"
		continue #empty string, we can't work under these conditions
	fi

	LAG_OID="$(echo "$LAG" | cut -d ' ' -f 1 | sed "s/$LAG_PORTS_OID.//")"
	log "Processing LAG with OID $LAG_OID"
	LAG_ID="$(snmpget -Ov -c $COMMUNITY -v 1 $DEVICE $LAG_ID_OID.$LAG_OID | cut -d ' ' -f 2)"
	log "LAG ID is $LAG_ID"
	#We split the hex values for the ports into segments of four, because that's how we get it back. no idea why.
	#then convert each one into an integer
	PORTS="$(echo "$LAG" | cut -d ':' -f 2 | xargs -n 4 | sed 's/ //g')"
	PORT_COUNT="$(echo "$PORTS" | wc -l)"
	PORT_UP_COUNT=0
	while read -r PORT; do
		PORT_ID="$((0x$PORT))"
		#-Ov: Just the result of the get, not the oid.
		PORT_DESC="$(snmpget -Ov -c $COMMUNITY -v 1 $DEVICE $PORT_DESC_OID.$PORT_ID | cut -d ' ' -f 2-)"
		PORT_LACP_STATUS="$(snmpget -Ov -c $COMMUNITY -v 1 $DEVICE $PORT_LACP_STATUS_OID.$LAG_OID.$PORT_ID | cut -d ' ' -f 2-)"
		case $PORT_LACP_STATUS in
			1) PORT_LACP_STATUS="operation"; ((PORT_UP_COUNT=PORT_UP_COUNT+1)) ;;
			2) PORT_LACP_STATUS="down" ;;
			3) PORT_LACP_STATUS="blocked" ;;
			4) PORT_LACP_STATUS="inactive" ;;
			5) PORT_LACP_STATUS="pexforceup" ;;
		esac
		log "Port with id $PORT_ID ($PORT_DESC) is $PORT_LACP_STATUS"
	done <<< "$PORTS"
	
	if [ $PORT_UP_COUNT -eq 0 ]; then
		MORE_INFO="$MORE_INFO\n(Ignoring)"
		LAG_COUNT="$(echo "$LAG_COUNT-1" | bc)"
	elif [ $PORT_UP_COUNT -lt $PORT_COUNT ]; then
		if [ $RETURN -lt 1 ]; then 
			PROBLEM_CHILD="$LAG_ID"
			RETURN=1
		fi #only set it to warning if there is no other more severe thing already happening.
		MORE_INFO="$MORE_INFO\n---> Only" #emphasis
	elif [ $PORT_UP_COUNT -eq $PORT_COUNT ]; then
		MORE_INFO="$MORE_INFO\nAll"
	else
		MORE_INFO="$MORE_INFO\n???"
		RETURN=3
	fi
	MORE_INFO="$MORE_INFO $PORT_UP_COUNT of the $PORT_COUNT ports in LAG $LAG_ID are up"
	
done <<< "$LAGS"

case $RETURN in
	0) echo "OK: All $LAG_COUNT LAGs in use on this box are fully operational" ;;
	1) echo "WARNING: LAG $PROBLEM_CHILD is not fully operational" ;;
	2) echo "CRITICAL: LAG $PROBLEM_CHILD is completely offline" ;;
	3) echo "UNKNOWN: There is a problem checking the lag status on this box" ;;
esac
if [ "$RETURN" -ne "0" ]; then
	echo "Recommend logging into $DEVICE and running 'show lag id $PROBLEM_CHILD' for more information"
fi
printf "$MORE_INFO"
echo
exit $RETURN

