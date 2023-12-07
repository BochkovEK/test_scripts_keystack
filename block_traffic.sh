#!/bin/bash

# The script blocks all traffic to and from the IP list nodes.
# The script must be copied to the desired compute node and run using the ssh command from another node.

TIMEOUT=180

# IPS nodes list
#example: BLOCKED_IPS=("<IP_ctrl_1>" "<IP_ctrl_2>" "<IP_3>" "...")
BLOCKED_IPS=("10.224.133.138" "10.224.133.139" "10.224.133.133" "10.224.133.134" "10.224.133.135")

block_traffic () {
    for IP in "${BLOCKED_IPS[@]}"; do
# Blocking incoming traffic from IP
        echo "Block incoming traffic from ${IP}"
        iptables -A INPUT -s "$IP" -j DROP
#Blocking outgoing traffic to IP
        echo "Block outgoing traffic to ${IP}"
        iptables -A OUTPUT -d "$IP" -j DROP
        date
    done
}

enable_traffic () {
    for IP in "${BLOCKED_IPS[@]}"; do
# Deleting incoming traffic rule from IP
        echo "Deleting incoming traffic rule from $IP"
        iptables -D INPUT -s "$IP" -j DROP
# Deleting outgoing traffic rule from IP
        echo "Deleting outgoing traffic rule from $IP"
        iptables -D OUTPUT -d "$IP" -j DROP
        date
    done
}

block_traffic
echo "The server is isolated from: ${BLOCKED_IPS[*]}"
iptables -S
sleep $TIMEOUT
enable_traffic
