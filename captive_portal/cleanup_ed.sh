#!/bin/bash
downstream_if=test_br
iptables -D FORWARD -i $downstream_if -j REJECT
iptables -D FORWARD -o $downstream_if -j DROP
