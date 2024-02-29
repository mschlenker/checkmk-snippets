#!/bin/bash

# (c) 2024 Mattias Schlenker for Checkmk GmbH
# License: GPL v2

# Specify the virtual network to use, can be overwritten using a file
# bridgeconfig.cfg that must exist in the current working directory:
VIP="10.23.11.1"
MASK="24"
VNET="10.23.11.0/24"
DUMMY="vmdummy0"
BRIDGE="vmbridge0"
TAPRANGE="0 9"

# The config file also can contain entries for WIFI/ETH interfaces.
# Separate them using whitespace
# PHYIFACES="wlp114s0 enp0s31f6 enbx00decafbad00"
#
# The tap user should be read from the sudo user, but can be specified:
# TAPUSER="hhirsch"
PHYIFACES=""
TAPUSER=""

if [ -f ./bridgeconfig.cfg ] ; then
    echo "Reading config from file: `pwd`/bridgeconfig.cfg:"
    cat ./bridgeconfig.cfg
    . ./bridgeconfig.cfg
fi

# Find settings that were not specified via config:
if [ -z "$TAPUSER" ] ; then
    TAPUSER="$SUDO_USER"
fi
if [ -z "$PHYIFACES" ] ; then
    PHYIFACES="` ip link ls | grep -v '^\s' | awk -F ': ' '{print $2}' | grep -e 'wl[opx]' `"
    PHYIFACES="${PHYIFACES}` ip link ls | grep -v '^\s' | awk -F ': ' '{print $2}' | grep -e 'en[opx]' `"
fi
# Exit if configuration is invalid
if [ -z "$TAPUSER" ] ; then
    echo "Please run this script either using sudo or specify the TAPUSER via ./bridgeconfig.cfg."
    exit 1
fi
if [ -z "$PHYIFACES" ] ; then
    echo "Please use ./bridgeconfig.cfg to specify the outgoing interfaces via PHYIFACES."
    exit 1
fi
if [ "$UID" -gt 0 ] ; then
    echo "Please run as root. Exiting."
    exit 1
fi

if ip link show $DUMMY > /dev/null 2>&1 ; then
	echo "Interface $DUMMY exists. Skipping..."
else
	ip link add $DUMMY type dummy
	echo "Checking $DUMMY:"
	ip link show $DUMMY
fi

if ip link show $BRIDGE > /dev/null 2>&1 ; then
	echo "Interface $BRIDGE exists. Skipping..."
else
	ip link add name $BRIDGE type bridge
	ip link set dev $BRIDGE up
	ip link set dev $DUMMY master $BRIDGE
	echo "Checking $BRIDGE:"
	ip link show $BRIDGE
fi

for n in `seq $TAPRANGE` ; do 
	if ip link show vmtap${n} > /dev/null 2>&1 ; then
		echo "Interface vmtap${n} exists. If you want to recreate, tear down first with:"
        echo "ip tuntap del dev vmtap${n} mode tap"
	else
        echo "Creating tap interface: vmtap${n} owned by $TAPUSER"
		ip tuntap add dev vmtap${n} mode tap user $TAPUSER group $TAPUSER
        ip link set vmtap${n} master $BRIDGE;
        ip link set dev vmtap${n} up
	fi
done

ip a add ${VIP}/${MASK} dev $BRIDGE > /dev/null 2>&1
ip route add $VNET via $VIP > /dev/null 2>&1

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1

# This is not nice, it forwards all traffic from the virtual net to each device...
# The result is having test VMs spamming the VPN.

# iptables -A FORWARD -j ACCEPT
# iptables -t nat -s $VNET -A POSTROUTING -j MASQUERADE

# This is better, forward only to physical interfaces specified above:
for iface in $PHYIFACES ; do
    iptables -A FORWARD -i $BRIDGE -o $iface -j ACCEPT
    iptables -A FORWARD -i $iface -o $BRIDGE -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -s $VNET -o $iface -j MASQUERADE
done

# Check the state of the DHCP server:

DHCPERR=0
if grep $BRIDGE /etc/default/isc-dhcp-server > /dev/null 2>&1 ; then
    echo "Found bridge in /etc/default/isc-dhcp-server"
else
    DHCPERR=$(( $DHCPERR + 1 ))
fi
if grep "routers $VIP" /etc/dhcp/dhcpd.conf > /dev/null 2>&1 ; then
    echo "Found gateway IP in /etc/dhcp/dhcpd.conf"
else
    DHCPERR=$(( $DHCPERR + 1 ))
fi

if [ "$DHCPERR" -lt 1 ] ; then
    echo "Restarting DHCP server..."
    systemctl restart isc-dhcp-server
    echo 'Have fun!'
    exit 0
fi

# If we have an incomplete DHCP configuration, give the user some hints on how to set up:
echo ""
echo "The virtual network is running, but no DHCP is available yet. Thus you might"
echo "use a static configuration for your clients with these parameters:"
echo ""
echo "Network: $VNET"
echo "Gateway: $VIP"
echo "DNS:     1.1.1.1"
echo ""
echo "In case you want to run a DHCP server (recommended), install isc-dhcp-server"
echo "and use this configuration:"
echo ""
echo "# /etc/dhcp/dhcpd.conf"

SUBNET=` echo $VNET | awk -F '/' '{print $1}'`
NETPREF=` echo $SUBNET | awk -F '.' '{print $1"."$2"."$3}'`

cat << EOF
option domain-name "checkmk.example";
option domain-name-servers 1.1.1.1;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;
subnet $NETPREF.0 netmask 255.255.255.0 {
  range $NETPREF.100 $NETPREF.199;
  option routers $VIP;
}

EOF

echo "# /etc/default/isc-dhcp-server"

cat << EOF
INTERFACESv4="$BRIDGE"
INTERFACESv6=""

EOF

echo "Just restart isc-dhcp-server after changing the config, next time this will be"
echo "done automatically."
echo ""
echo 'Have fun!'
