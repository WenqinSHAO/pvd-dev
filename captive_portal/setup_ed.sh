#!/bin/bash
set -e 
# allow forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

downstream_if=test_br

# by default, block all traffic to and from the downstream interface
iptables -I FORWARD -i $downstream_if -j REJECT
iptables -I FORWARD -o $downstream_if -j DROP
ip6tables -I FORWARD -i $downstream_if -j REJECT
ip6tables -I FORWARD -o $downstream_if -j DROP

# To add an exception for a specific ip:
#sudo iptables -I FORWARD -i $downstream_if -s 192.168.1.2 -j ACCEPT
#sudo iptables -I FORWARD -o $downstream_if -d 192.168.1.2 -j ACCEPT
