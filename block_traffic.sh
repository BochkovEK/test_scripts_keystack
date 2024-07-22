#!/bin/bash

# The script blocks all traffic to and from the IP list nodes.
# The script must be copied to the desired compute node and run using the ssh command from another node.
# For start this script, need create file ~/blocked_ips_list
# ~/blocked_ips_list example:
#<IP_1>
#<IP_2>
#<IP_3>
#<IP_4>

echo 'Start block_traffic.sh script'
if [ -f ~/blocked_ips_list ]; then BLOCKED_IPS=$(cat ~/blocked_ips_list); else echo "IPS list to block not found (~/blocked_ips_list)"; exit 1; fi
#[[ -z $BLOCKED_IPS ]] && { echo "IPS list to block not found (env BLOCKED_IPS)"; exit 1; }

TIMEOUT=180

block_traffic () {
    for IP in ${BLOCKED_IPS}; do
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
    for IP in ${BLOCKED_IPS}; do
# Deleting incoming traffic rule from IP
        echo "Deleting incoming traffic rule from $IP"
        iptables -D INPUT -s "$IP" -j DROP
# Deleting outgoing traffic rule from IP
        echo "Deleting outgoing traffic rule from $IP"
        iptables -D OUTPUT -d "$IP" -j DROP
        date
    done
}

check_ips_list () {
  echo "check ips list..."
  BLOCKED_IPS=$(cat ~/blocked_ips_list) #"a b c d"
  [[ -z $BLOCKED_IPS ]] && { "BLOCKED_IPS is empty"; exit 1; }
    for IP in ${BLOCKED_IPS}; do
        echo "$IP"
    done
}

check_ips_list
block_traffic
echo "The server is isolated from: ${BLOCKED_IPS[*]}"
#iptables -S
sleep $TIMEOUT
enable_traffic
