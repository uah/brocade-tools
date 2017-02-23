# Brocade Tools

These tools exist to help network administrators wrangle Brocade ICX gear, especially during a migration from Cisco Catalyst access/distribution-layer gear.

If you have questions or trouble with these tools, my contact information is located on [my github profile](https://github.com/hf0002) and in [the UAH directory](http://uah.edu/directory).

* **brocadinator.sh**: As arguments, provide the path to a Cisco IOS config file, and the number of the Brocade ICX stack-unit that will replace it. Standard output will be a Brocade ICX VLAN and port-name config. Load this on the ICX and then unplug the cables from the Cisco and plug them one-for-one into the ICX.
  * Be sure to check your tagged (trunk) ports or odd port configs, especially native vlan. This is only really effective for untagged (access) ports.
  
* **macdump.sh**: As arguments, provide a space-separated list of Cisco switch IPs. The script will log into the switches as you, and output every MAC-to-port association that is currently present. You can run this multiple times during the day and then pipe through "sort -u" to prune duplicates. This will prepare a file to load into macload.sh.
* **macload.sh**: As arguments, provide the IP of the Brocade switch you just plugged everything into, followed by the name of the file created by macdump.sh. The script will produce an ICX config that will place every MAC in the same VLAN it was in at the time you ran the macdump.sh script on the Cisco switch.

* **showvlan_to_portids.sh**: Pipe the output from 'show vlan 4000' (or whatever VLAN) into this script and it will generate interface IDs for the ports in that VLAN. This can help you move a lot of ports from one VLAN to another, for instance.
