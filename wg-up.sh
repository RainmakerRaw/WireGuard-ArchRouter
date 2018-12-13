# A script to bring up the WireGuard VPN interface, and set up the VPN routing table (with rules for the correct subnet).

#!/usr/bin/bash
ip link add dev azirevpn-uk1 type wireguard
ip address add dev azirevpn-uk1 10.20.xx.xx/19
wg setconf azirevpn-uk1 /etc/wireguard/azirevpn-uk1.conf
ip link set up dev azirevpn-uk1
ip rule add unicast iif [WAN interface] table vpn
ip route add default dev azirevpn-uk1 via 10.xx.xx.xx table vpn
ip route add 192.168.2.0/24 via 192.168.2.1 dev [LAN interface] table vpn
