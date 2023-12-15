#!/bin/bash

#The script copy block_traffic script to node and start it by ssh

# BLOCKED_IPS=("<IP_ctrl_1>" "<IP_ctrl_2>" "<IP_3>" "...")
BLOCKED_IPS=("10.224.133.138" "10.224.133.139" "10.224.133.133" "10.224.133.134" "10.224.133.135") && \

[[ -z $NODE_TO_BLOCK_TRAFFIC ]] && NODE_TO_BLOCK_TRAFFIC=""

while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
        -n,     -node             <node_name>
"
      exit 0
      break ;;
	  -n|-node) NODE_TO_BLOCK_TRAFFIC="$2"
	    echo "Found the -node <node_name> option, with parameter value $NODE_TO_BLOCK_TRAFFIC"
      shift ;;
    --) shift
      break ;;
    *) echo "$1 is not an option";;
      esac
      shift
done

[[ -z $NODE_TO_BLOCK_TRAFFIC ]] && { echo "node name needed to block traffic (env NODE_TO_BLOCK_TRAFFIC) or start this script with key -n <node_name>"; exit 1; }

scp ./block_traffic.sh "$NODE_TO_BLOCK_TRAFFIC":~/
ssh -o StrictHostKeyChecking=no "$NODE_TO_BLOCK_TRAFFIC" 'chmod 777 ~/block_traffic.sh'
ssh -t -o StrictHostKeyChecking=no "$NODE_TO_BLOCK_TRAFFIC" 'echo '"${BLOCKED_IPS[*]}"' > ~/blocked_ips_list'
ssh -t -o StrictHostKeyChecking=no "$NODE_TO_BLOCK_TRAFFIC" 'bash ~/block_traffic.sh'

