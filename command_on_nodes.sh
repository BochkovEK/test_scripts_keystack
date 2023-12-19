#!/bin/bash

#The scrip starts command on nodes

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

comp_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"
nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

[[ -z $COMMAND ]] && COMMAND="ls -la"
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

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { COMMAND=$1; echo "Command parameter found with value $COMMAND"; }
}

count=1
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -c, 	-command        <command>
        -t, 	-type_of_nodes  <type_of_nodes> 'ctrl', 'comp', 'net'
"
      exit 0
      break ;;
	-c|-command) COMMAND="$2"
	    echo "Found the -command <command> option, with parameter value $COMMAND"
      shift ;;
  -t|-type_of_nodes)
      note_type_func "$2"
      shift ;;
  --) shift
    break ;;
  *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }

echo "${NODES[*]}"

for host in "${NODES[@]}"; do
  echo "Check container $CONTAINER_NAME on ${host}"
  ssh -o StrictHostKeyChecking=no -t "$host" "$COMMAND"
done
