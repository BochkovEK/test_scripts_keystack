#!/bin/bash
# test push
# IPS controls list
#BLOCKED_IPS=("10.224.51.11" "10.224.51.12" "10.224.51.13" "10.224.51.2" "10.224.51.4")
BLOCKED_IPS=("10.224.133.138" "10.224.133.139" "10.224.133.133" "10.224.133.134" "10.224.133.135")

block_traffic () {
    for IP in "${BLOCKED_IPS[@]}"; do
# Blocking incoming traffic from IP
        echo "Block incoming traffic from ${IP}"
        iptables -A INPUT -s $IP -j DROP
#Blocking outgoing traffic to IP
        echo "Block outgoing traffic to ${IP}"
        iptables -A OUTPUT -d $IP -j DROP
        date
    done
}

enable_traffic () {
    for IP in "${BLOCKED_IPS[@]}"; do
# Deleting incoming traffic rule from IP
        echo "Deleting incoming traffic rule from IP"
        iptables -D INPUT -s ${IP} -j DROP
# Deleting outgoing traffic rule from IP
        echo "Deleting outgoing traffic rule from IP"
        iptables -D OUTPUT -d ${IP} -j DROP
        date
    done
}

block_traffic
echo "The server is isolated from ${BLOCKED_IPS[@]}"
iptables -S
#sleep 180
#enable_traffic
