#!/bin/bash

#The scrip check container state on nodes or node

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

comp_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"
nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

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

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { CONTAINER_NAME=$1; echo "Name container parameter found with value $CONTAINER_NAME"; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      <container_name> as parameter
      -c, 	-container_name		<container_name>
      -t, 	-type_of_nodes		<type_of_nodes> 'ctrl', 'comp', 'net'
"
      exit 0
      break ;;
	  -c|-container_name) CONTAINER_NAME="$2"
	    echo "Found the -container_name <container_name> option, with parameter value $CONTAINER_NAME"
      shift ;;
    -t|-type_of_nodes)
      echo "Found the -type_of_nodes  with parameter value $2"
      note_type_func "$2"
      shift ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done

[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }

echo "Nodes for container checking:"
echo "${NODES[*]}"

for host in "${NODES[@]}"; do
  echo "Check container $CONTAINER_NAME on ${host}"
  if ping -c 2 $host &> /dev/null; then
    printf "%40s\n" "There is a connection with $host - ok!"
    ssh -o StrictHostKeyChecking=no -t $host docker ps | grep "$CONTAINER_NAME" | \
      sed --unbuffered \
        -e 's/\(.*(unhealthy).*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*restarting.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*(healthy).*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*Up.*\)/\o033[92m\1\o033[39m/'
  else
    printf "%40s\n" "${red}No connection with $host - error!${normal}"
    echo -e "${red}The node may be turned off.${normal}\n"
  fi
done
