#!/bin/bash

VIP="10.23.11.1"
MASK="24"
VNET="10.23.11.0/24"
WIFI="wlp114s0"
ETH="enp0s31f6"

if ip link show dummy0 ; then
	echo "Interface dummy0 exists. Skipping..."
else
	ip link add dummy0 type dummy
	echo "Checking dummy0:"
	ip link show dummy0
fi

if ip link show br0 ; then
	echo "Interface br0 exists. Skipping..."
else
	ip link add name br0 type bridge
	ip link set dev br0 up
	ip link set dev dummy0 master br0
	echo "Checking  br0:"
	ip link show br0
fi

for n in `seq 0 9` ; do 
	if ip link show tap${n} ; then
		echo "Interface tap${n} exists. Skipping..."
	else
		tunctl -u root ; ip link set tap${n} master br0; ip link set dev tap${n} up
	fi
done

ip a add ${VIP}/${MASK} dev br0
ip route add $VNET via $VIP

sysctl -w net.ipv4.ip_forward=1

# This is not nice, it forwards all traffic from the virtual net to each device...
# The result is having test VMs spamming the VPN.

# iptables -A FORWARD -j ACCEPT
# iptables -t nat -s $VNET -A POSTROUTING -j MASQUERADE

iptables -A FORWARD -i br0 -o $WIFI -j ACCEPT
iptables -A FORWARD -i $WIFI -o br0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i br0 -o $ETH  -j ACCEPT
iptables -A FORWARD -i $ETH  -o br0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -s $VNET -o $WIFI -j MASQUERADE
iptables -t nat -A POSTROUTING -s $VNET -o $ETH  -j MASQUERADE

systemctl restart isc-dhcp-server

exit $?

# /etc/dhcp/dhcpd.conf

option domain-name "example.org";
option domain-name-servers 8.8.8.8;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;
subnet 10.23.11.0 netmask 255.255.255.0 {
  range 10.23.11.100 10.23.11.199;
  option routers 10.23.11.1;
  option domain-name-servers 8.8.8.8;
}

# /etc/default/isc-dhcp-server

INTERFACESv4="br0"
INTERFACESv6=""

