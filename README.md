# Brocade Tools
These tools exist to help network administrators wrangle Brocade ICX gear.

* **showvlan_to_portids.sh**: Pipe the output from 'show vlan 4000' (or whatever VLAN) into this script and it will generate interface IDs for the ports in that VLAN. This can help you move a lot of ports from one VLAN to another, for instance.
