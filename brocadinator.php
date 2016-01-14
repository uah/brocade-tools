#!/usr/bin/env php
<?php

if ( ! array_key_exists(2,$argv) ) {
	error_log("First arg is a Cisco IOS config file.");
	error_log("Second arg is the stack member number that will replace it (the first number in the interface specification).");
	die();
}

$member = $argv[2];
$file = $argv[1];

error_log("Reading " . $file . "...");
$c = file_get_contents($file);
if ( $c == "" ) { die(error_log("I couldn't read that file. Sorry.")); }
if ( preg_match('/^hostname (.+)$/m',$c,$hostname) ) {
	$hostname = $hostname[1];
} else {
	$hostname = "switch";
}
error_log("Converting ports from " . $hostname . " into stack member number " . $member . "...");

error_log("Loading interfaces...");
preg_match_all('/\sinterface .+\n(.*)\!/sU',$c,$interfaces);

$untagged = array();
$tagged = array();
$descriptions = array();
$modinc = 0; //hhow far to increment the module number... increases if we go from fast0/... to gig0/... for instance
$oldcat = ""; //what was the name of the last interface category we saw (something like GigabitEthernet)

for ( $i = 0; $i < count($interfaces[0]); $i++ ) {
	preg_match('/^interface (.+)$/m',$interfaces[0][$i],$name);
	if ( strpos($name[1],'/') === false ) {
		//the int name doesnt have a slash so its either an svi for a vlan or the out of band mgmt port on the back of a 3560-X or 3850
		error_log("Skipping " . $name[1] . " because it's irrelevant to us");
	} elseif ( ( strpos($interfaces[1][$i],"switchport mode trunk") === false ) && ( strpos($interfaces[1][$i],"switchport access vlan") === false ) ) {
		error_log("Skipping " . $name[1] . " because it doesn't have an access or trunk port config");
	} else {
		preg_match('/^(\D+)([0-9])\/([0-9]+)/',$name[1],$namep);

		if ( $namep[1] != $oldcat ) {
			//our category changed! so we increment the module counter on the brocade side... even if cisco didnt
			//TODO: we will break on a 3560G (or produce invalid eth names like 1/1/49) because a 3560G just uses gig0/49-52 for its sfp cage interfaces... whyyyyyyyyyy
			$modinc++;
			$oldcat = $namep[1];
		}

		$newname = "eth " . $member . "/" . ($namep[2]+$modinc) . "/" . ($namep[3]);

		$istrunk = preg_match('/^ switchport mode trunk/m',$interfaces[1][$i]);
		if ( $istrunk ) {
			$mode = "tagged";
			preg_match('/^ switchport trunk native vlan ([0-9]+)$/m',$interfaces[1][$i],$vlan);
			//this will be the trunks native vlan. we dont really do anything with this because in brodade land we should tag all vlans - no native vlan. but i will print it to standard error later for S&G
			$vlan = $vlan[1];
			$tagged[] = $newname;
		} else {
			$mode = "untagged";
			preg_match('/^ switchport access vlan ([0-9]+)$/m',$interfaces[1][$i],$vlan);
			$vlan = $vlan[1];
			$untagged[$vlan][] = $newname;
		}

		$hasdesc = preg_match('/^ description (.+)$/m',$interfaces[1][$i],$desc);
		if ( $hasdesc ) {
			$descriptions[$newname] = $desc[1];
		}

		error_log($name[1] . " becomes " . $newname . " - " . $mode . " port (VLAN" . $vlan . ")");
	}
}

error_log("Generating vlan configs"); //finally
$vlans = array_keys($untagged);
foreach ($vlans as $i) {
	echo("vlan " . $i . "\n");
	echo("spanning-tree 802-1w\n"); //and whatever other configs for vlan level

	//now if we dont chunk this garbage the switch will balk if we put a load of ports on one line
	$uchunks = array_chunk($untagged[$i],8);
	foreach ($uchunks as $j) {
		echo("untagged " . implode(" ",$j) . "\n");
	}
	echo("tagged " . implode(" ",$tagged) . "\n");
}

error_log("Generating port-name configs");
$ints = array_keys($descriptions);
foreach ( $ints as $i ) {
	echo("int " . $i . "\n");
	echo("port-name " . $descriptions[$i] . "\n"); //and whatever other int level configs
}

#echo("end\n"); //dont actually do this cause we may have more stack members to config!
echo("\n\n"); //just give a little delimiter
error_log("Done!");

