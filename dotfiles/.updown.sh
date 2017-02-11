#!/bin/sh

# http://serverfault.com/questions/382498/howto-only-tunnel-specific-hosts-route-through-openvpn-client-on-tomato
# https://vpnac.com/knowledgebase/86/TomatoUSB-policy-based-routing-howto.html

# delete alternate routing table
ip route flush table 100

# stop split tunnel
RULE=`ip rule | grep "lookup 100" | wc -l`
if [ "$RULE" -gt 0 ]; then
  ip rule del fwmark 1 table 100
fi

# force routing system to recognize our changes
ip route flush cache

iptables -t mangle -F PREROUTING

# logger vpnrouting: clean-up

if [ $script_type == 'up' ]
then
  # disable reverse path filtering
  for i in /proc/sys/net/ipv4/conf/*/rp_filter ; do
    echo 0 > $i
  done

  ip route show table main | grep -Ev ^default | grep -Ev $dev \
    | while read ROUTE ; do
        ip route add table 100 $ROUTE
  done

  # add WAN as default gateway
  ip route add table 100 default via $(nvram get wan_gateway_get)

  # start split tunnel
  ip rule add fwmark 1 table 100

  # force routing system to recognize our changes
  ip route flush cache

  # bypass VPN
  iptables -t mangle -A PREROUTING -i br1 -j MARK --set-mark 1

  # use VPN
  iptables -t mangle -A PREROUTING -i br0 -j MARK --set-mark 0

  iptables -I INPUT -i $dev -j ACCEPT
  iptables -I FORWARD -i $dev -j ACCEPT
  iptables -t nat -I POSTROUTING -o $dev -j MASQUERADE
  # iptables -t nat -I POSTROUTING -o ppp0 -j MASQUERADE

  # logger vpnrouting: tunnel splitted
else
  # enable reverse path filtering
  for i in /proc/sys/net/ipv4/conf/*/rp_filter ; do
    echo 1 > $i
  done
  service firewall restart
fi
