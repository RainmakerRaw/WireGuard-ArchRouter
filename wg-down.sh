#!/usr/bin/bash
ip link set down dev azirevpn-uk1
ip link del dev azirevpn-uk1
ip rule del unicast iif [WAN interface, eg enp3s0f0] table vpn