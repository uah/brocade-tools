#!/usr/bin/env bash

#Load a csv of vlan/mac pairs and load it into a brocade switch depending on what port those macs are on

function log() {
	echo "$@" >&2
}

IP=$1

if [[ $IP == --help ]] || [[ $IP == -h ]]; then
	log "usage: $0 [host-or-ip] [file-from-macdump]" 
	exit 127
fi

if [ -z "$IP" ]; then
	log "The first argument is the switch IP into which you want to load these VLAN assignments. The second arg is a csv file from macdump."
	exit 
fi


if [ -z "$SSHPASS" ]; then
	#log "You are $(id $USER)"
	read -sp "Password for logging into switches as $(whoami): " SSHPASS >&2
	log
fi
if [ -z "$SSHPASS" ]; then
	log "Error: You have to provide a password!"
	exit 4
fi
export SSHPASS

log -n "Reading your dump file... "
DUMP=$(cat "$2")
log "done"

IP=$1

log -n "Reading destination switch mac table (this will take forever)... "
DESTMACS=$(/usr/libexec/rancid/flogin -c "show mac-address" $1 | grep "Dynamic")
log "done"

#Strip all the MACs that are in a LAG on the module 2 fiber card. (HACK HACK HACK)
DESTMACS=$(echo "$DESTMACS" | grep -vE '\/2\/.*[\*\-].*\/2\/')
#echo "$DESTMACS" && exit

CONFIG="conf t"

VLANS=$(echo "$DUMP" | cut -d , -f 1 | sort -u | xargs)

for VLAN in $VLANS; do
	log -n "$VLAN"
	CONFIG+="
	vlan $VLAN
	spanning-tree 802-1w"

	VLANDUMP=$(echo "$DUMP" | grep -E "^$VLAN,")
	while read -r LINE; do
		FOUND=$(echo "$DESTMACS" | grep "$(echo $LINE | cut -d , -f 2)")
		if [ "$?" -ne 0 ]; then
			#that mac is not on this switch
			log -n "."
		else 
			#found on this switch
			NEEDSLOAD=$(echo "$FOUND" | awk '{print $4}' | grep "^$VLAN")
			if [ "$?" -ne 0 ]; then
				#it needs loading
				CONFIG+="
untagged e $(echo $FOUND | awk '{print $2}')"
				log -n "L"
			else
				#port already in the right VLAN.
				log -n "!"
			fi
		fi
	done <<< "$VLANDUMP"

	CONFIG+="
	exit"
done
CONFIG+="
end
exit
exit"

log
log "Your config is ready." 
log

echo "$CONFIG"
