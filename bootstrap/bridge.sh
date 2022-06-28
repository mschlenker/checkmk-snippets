#!/bin/bash

# Start a bridge with NetworkManager. This even works for
# WiFi, but must take place after associating to an access point.

iface="$1"

if ip link show dev br0 ; then
	echo "Bridge exists, skipping..."
elif [ -z "$iface" ] ; then
	echo "No interface specified to bridge to, use one of those:"
	nmcli con show
	exit 1
fi

echo "Before:"
nmcli con show
nmcli con add type bridge ifname br0
nmcli con add type bridge-slave ifname "$iface" master br0
nmcli con up br0
echo "After:"
nmcli con show

# Create tun/tap devices 
for n in ` seq 0 9 ` ; do
        tunctl -u root
        ip link set tap${n} master br0
        ip link set dev tap${n} up
done
