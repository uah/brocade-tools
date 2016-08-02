#!/usr/bin/env bash

#Dump all the macs from a Cisco switch's mac table into a csv

trap 'ctrl_c "$@"' INT
function ctrl_c() {
	#throw the user a bone if they have to bail halfway
        log "Okay, bailing!"
	log "You still need to do these: $@"
	exit 200
} 

function log() {
	echo "$@" >&2
}

IP=$1

if [[ $IP == --help ]] || [[ $IP == -h ]]; then
	log "usage: $0 [host-or-ip]" 
	exit 127
fi

if [ -z "$IP" ]; then
	log "Supply a list of IPs for the switches whose MAC tables you want to dump." 
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

while [ -n "$1" ]; do

	IP=$1

	log -n "Discovering $IP."
	#we check if the switch is in our known hosts, so we pull the host key first
	KEY=$(ssh-keyscan -H $1 2>&1 | tail -n 1)
	log -n "."
	THEIMPORTANTPART=$(echo $KEY | cut -d ' ' -f 3)
	
	if [ -z "$THEIMPORTANTPART" ]; then
		#we didn't get a key back. probably couldn't connect at all
		log
		log "Can't ssh to $IP... Maybe it's an old switch without ssh?" 
		exit $?
	fi
	
	grep "$THEIMPORTANTPART" ~/.ssh/known_hosts > /dev/null
	if [ $? -ne 0 ]; then
		log -n "! " #echo -n ". Adding $IP to your known hosts. "
		echo "$KEY" >> ~/.ssh/known_hosts
	else
		log -n ". "
	fi
	log
	
	log "Discovering MACs..."
	SWITCHMACS=$(sshpass -e ssh $IP show mac address-table | dos2unix | grep -vE '(CPU)' | grep DYNAMIC | awk "{print \$1 \",\" \$2 \",\" \$4 \",$IP\"}" 2>/dev/null)
	for PORT in $(echo "$SWITCHMACS" | cut -d , -f 3 | sort -u | xargs); do
		if [ "$(echo "$SWITCHMACS" | grep -cE "$PORT,")" -gt "10" ]; then
			log "$PORT has more than 10 MACs - stripping"
			SWITCHMACS="$(echo "$SWITCHMACS" | grep -vE "$PORT")"
		fi
	done
	echo "$SWITCHMACS"
	
	log "Done with $IP!" 
	shift
	log
done

