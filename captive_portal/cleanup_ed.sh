#!/bin/bash
downstream_if=vr2e1
iptables -D FORWARD -i $downstream_if -j REJECT
iptables -D FORWARD -o $downstream_if -j DROP
