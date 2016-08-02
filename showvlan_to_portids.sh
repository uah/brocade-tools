#!/usr/bin/env bash
#set -x

if [ "$1" == "--help" ]; then
	echo "Pipe or paste the output from 'show vlan 4000' into this script."
	echo "You can supply one argument, which is a string to prepend to each"
	echo "line full of port ids. So if you did 'show vlan 4000' and piped it"
	echo "into this script, and that VLAN has ports 1/1/1, 1/1/2, and 2/1/37"
	echo "in it, and you provided the argument 'no untag' to this script,"
	echo "you will get output like:"
	echo "no untag eth 1/1/1 eth 1/1/2"
	echo "no untag eth 2/1/37"
	exit 1
fi

PREFIX="$1"

sponge | grep -vE 'Legend|None|Disabled|PORT-VLAN' | while read LINE; do
	if [ -n "$LINE" ]; then
		echo
		echo -n "$PREFIX "
		MOD="$(echo $LINE | sed -e 's/.*(//' -e 's/).*//' -e 's/[UM]//g')"
		for PORT in $(echo $LINE | sed -e 's/.*)//'); do
			echo -n "eth $MOD/$PORT "
		done
	fi
done
echo

	
