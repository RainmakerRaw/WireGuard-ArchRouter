# WireGuard x86 edge router, using Arch Linux
How to make a fully functional Arch Linux edge router, with stateful firewall and NAT, running WireGuard VPN.

This readme has been cobbled together in an hour because I didn't want to just post my reference files without comment. This guide will be fleshed out and formatted nicely over the coming day(s) as I get the opportunity **[It never was, but I'm glad some people found it useful!]**, and will ultimately include full copies of all referenced config files etc. For now, anyone who is attempting this project should have a fair understanding of Linux anyway, so I assume you know how to parse my cut down config example files and amend your own (full versions) to match.

I also start this guide by assuming that you are running the latest Arch Linux, you are using AzireVPN as your VPN provider, and you have at least three physical interfaces - WAN, LAN and DMZ (for your NAS/servers). You can amend this guide easily to account for any differences.

For now, in essence:

Install the latest Arch Linux, following the Arch Wiki's installation guide if necessary. You may wish to consider a switch to the `linux-lts` and `linux-lts-headers` kernel to save updates needing reboots as often as time goes on. Just add them, remove the normal linux package, and then regenerate the GRUB config file. Next time you reboot you're on LTS (or hardened, or whatever).

I also assume that as part of that process you have set up your local network interfaces using netctl profiles (which live in `/etc/netctl`), and then enabled and started them. I'm using a repurposed Dell Optiplex 7010 from eBay with an additional low profile Intel Pro 1000 VT quad port server NIC, so my netctl profiles are `/etc/netctl/WAN`, `./LAN`, and `./DMZ`. They are enabled and started like this:

```shell
netctl enable eno1 #WAN
```
```shell
netctl enable enp3s0f0 #LAN
```
```shell
netctl enable enp3s0f1 #DMZ
```
```shell
netctl start emo1
````
```shell
netctl start en3ps0f0
```
```shell
netctl start en3ps0f1
```

In future, netctl will bring up and handle the interfaces by itself. 

Now the basics are out of the way, we install the basic requirements for this project:

```shell
pacman -S dhcp shorewall dnscrypt-proxy linux-headers wireguard-tools wireguard-dkms jq resolvconf iperf3 glances openssh
```

After a reboot, put your AzireVPN (or other) .conf file in `/etc/wireguard`. Edit it to remove references to DNS, add your private key and your provider's public key and endpoint, and have it wind up matching the example in this repo.

Next, edit `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` to enable the service on your interfaces (e.g. `127.0.0.1:53`, `192.168.1.1:53`, `192.168.2.1:53`). Enable whichever servers you prefer, for example Cloudflare and Quad9 - or whatever. Then enable dnscrypt-proxy:

```shell
systemctl enable --now dnscrypt-proxy
```

Next we need to tell Shorewall what to do. For simplicity's sake, first copy over the Three Interfaces example from the Shorewall documentation like this:

```shell
cp /usr/share/doc/shorewall/Samples/three-interfaces/* /etc/shorewall/
```

Edit the files in the `/etc/shorewall` directory as per the conf files in this repo. In essence, you need to edit the `./interfaces` file to list your interfaces by name, outline your network segments in `./zones`, tell Shorewall who can talk with whom using `./policy` and set up `./rules` with any necessary changes. Finally we set the `./snat` file to tell Shorewall that our LAN subnet should `MASQUERADE` via our VPN, and the DMZ zone should `MASQUERADE` via the WAN IP.

My example rules config file in this repo gives examples for allowing SSH from local clients only, and using DNAT to allow people on the internet as well as LAN and DMZ clients to access servers on local machines (without having to hairpin back through the firewall). Once this is done, we can enable and start shorewall:

```shell
systemctl enable --now shorewall
```

Then we need to set up dhcpd to serve our local clients with DHCP IP addresses (the ones who aren't issued static IPs, anyway). Edit `/etc/dhcpd.conf` and use the repo's example .conf file as a guide. Start it with `authoritative;` and amend the subnets to your liking (eg `172.16.32.0/24` instead of `192.168.1.0/24` or whatever). You can flesh out the example static IP hosts as or if required. Then start and enable the DHCPD's server:

```shell
systemctl enable --now dhcpd4
```

At this point, you may wish to configure and enable SSH so you can administer your router from elsewhere on your network. This is especially useful if (likely) you are to run the router headless. If you get stuck, check out the Arch SSH wiki, but in essence just edit `/etc/ssh/sshd.conf` to uncomment the port and to allow root login if required (only do this if not allowing WAN access to SSH, and even then it's probably a bad idea). Hardening SSH is beyond the scope of this guide (for now), but I can recommend `sshguard`.

Now we have the ability to form WireGuard tunnels, `dnscrypt-proxy` to resolve DNS for local clients, `dhcpd` to issue and track IP addresses, and `shorewall` to keep everything running smoothly and safely. With regards to bringing up and down the WireGuard tunnel itself, I don't use the `wg-quick` utility as it overwrites rules and makes its own tables - which in my particular case intefered with my preferred routing for my DMZ subnet. Instead I made two very simple shell scripts, `wg-up.sh` and `wg-down.sh`, which are fairly self-explanatory. 

Specifically, `wg-up.sh` brings up a WireGuard interface to AzireVPN (in my case). It then adds a table called `VPN` to `iproute2`'s `rt_tables`, and adds rules to it so that all traffic on my LAN subnet looks up this table. The rules in this table say:

```shell
ip rule add unicast iif {LAN interface} table vpn
```
```shell
ip route add default dev azirevpn-uk1 via 10.xx.xx.xx table vpn
```
```shell
ip route add 192.168.2.0/24 via 192.168.2.1 dev {DMZ interface} table vpn
```

This basically means if you're on my LAN you get sent to the WireGuard tunnel and everything is protected by the VPN. That is, however, unless you wish to access a machine on the DMZ subnet (`192.168.2.0/24`). In this case you're sent there directly by the router, bypassing the VPN. Everyone else (the firewall, the DMZ zone clients) get sent directly over WAN and bypass the tunnel. This was necessary for me to keep my servers running properly (Plex, SABnzbd, Sonarr etc) and be able to reach them using mydomain.com over the internet.

This is all very well and good, but bringing up the WireGuard interface, adding tables, fleshing out that table with rules and so on is time consuming. That's where my script comes in. I made a systemd unit to launch the `wg-up.sh` script on boot. Now any time my router (re)starts, within 10 seconds everything is up and online, and my WireGuard tunnel is ready for action too. Seamless!

To make the systemd service, make a file called wg-up.service (or whatever) and place it in `/etc/systemd/system/` with its contents as per the example file in this repo. Don't forget to place your scripts in `/root/` or else to amend the content of the service file to point to the right location. Then enable the service like any other, so it comes up at boot in future:

```shell
systemctl enable --now wg-up.service
```

If for any reason you want/need to restart your tunnel, you can just issue `/root/wg-down.sh` and then invoke your startup service again:

    systemctl restart wg-up.service

If you want to see the status of your WireGuard VPN tunnel you can always issue the ever-useful command `wg`. It's as simple as that. To test that things are working nicely, you can do the following *from the router itself*:

```shell
curl ipinfo.io #Should return WAN IP
```
```shell
curl ipinfo.io --interface azirevpn-uk1 #Should return AzireVPN's IP
```

We're all done! Now you should have a barebones, fully functional, powerful, stateful firewall with (D/S)NAT, WireGuard, network segregation between LAN and servers/CCTV/etc for security, and all the great tools (like `iperf3`, `traceroute`, `dig`, `ping`, `glances`, etc) that Linux affords. 

My own little Arch Router has been up for several ~~days~~ years now. I have two switches (one coming out of the LAN interface and one coming out of the DMZ interface), and my Unifi UAC AP PRO access point is plugged into the DMZ zone's PoE switch. The AP runs an SSID for us to use, and a captive portal for guests to our home, which is cut off from everything and everyone else. This provides convenience and security in one step. If we have a gathering (eg Christmas) I just put up a piece of paper with the WiFi SSID and password, and the relevant  QR code underneath so people can just hop onto the guest WiFI without asking.

You can see a little topology diagram of my network as it was when I first posted this repo (sans some recent changes like IPs, and my wireless AP is now in DMZ) here:

![My old network topology](https://i.imgur.com/6GAEsGf.png)

I'll tidy it up at some point to reflect the new reality of my network, but it still gives you a nice visual idea of what this guide accomplishes. Finally here's a speedtest from a LAN client using the WireGuard tunnel (with some wifi users browsing, so slightly low - you get the idea though): 

![Speedtest.net result using the Arch router](https://www.speedtest.net/result/7878355703.png)

So far on my 'router', the average load is 0.00 (lol). It puts through my full ISP line speed (380Mbs) without breaking double digits CPU usage (even via WireGuard - which spreads the load beautifully over the i7's 8 threads), and is using about 125MB RAM. Overkill? Certainly. Fun? Absolutely. Future-proof? Hell yeah. Try it out and let me know how you find it!

## Update
This router ran a couple of years for me, before I moved to vanilla BSD. It shovelled WireGuard over gigabit just as well as it did my old 380Mbps plan, and never went wrong. Kudos. 
These days, I'm on gigabit WAN and have a single x86 BSD edge router, a managed L2/L3 core switch, a Ruckus R710 Wireless AP managing guest isolation, and one flat subnet. I'm happy to see this guide helped a few people achieve similar goals. 
