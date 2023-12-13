#!/bin/bash

#The scrip check container state on nodes or node

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

comp_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"
nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME="consul"
[[ -z $NODES ]] && NODES=()
#======================

note_type_func () {
  case "$1" in
        ctrl)
          nodes_to_find=$ctrl_pattern
          echo "Сontainer will be checked on ctrl nodes"
          ;;
        comp)
          nodes_to_find=$comp_pattern
          echo "Сontainer will be checked on comp nodes"
          ;;
        net)
          nodes_to_find=$net_pattern
          echo "Сontainer will be checked on net nodes"
          ;;
        *)
          echo "type is not specified correctly. Сontainers will be checked on ctr, comp, net nodes"
          ;;
        esac
}

#======================
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -c, 	-container_name		<container_name>
        -t, 	-type_of_nodes		<type_of_nodes> 'ctrl', 'comp', 'net'
"
      exit 0
      break ;;
	-c|-container_name) CONTAINER_NAME="$2"
	    echo "Found the -t <container_name> option, with parameter value $CONTAINER_NAME"
      shift ;;
  -t|-type_of_nodes)
      note_type_func "$2"
      shift ;;
  --) shift
    break ;;
  *) echo "$1 is not an option";;
    esac
    shift
done

[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }

echo "${NODES[*]}"

for host in "${NODES[@]}"; do
  echo "Check container $CONTAINER_NAME on ${host}"
  ssh -o StrictHostKeyChecking=no -t $host docker ps | grep "$CONTAINER_NAME" | \
      sed --unbuffered \
        -e 's/\(.*healthy.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*unhealthy.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*restarting.*\)/\o033[31m\1\o033[39m/'
done
