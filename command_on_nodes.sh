#!/bin/bash

#The scrip starts command on nodes

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

[[ -z $COMMAND ]] && COMMAND="ls -la"
[[ -z $NODES ]] && NODES=()
[[ -z $PING ]] && PING="false"
#======================

note_type_func () {
  case "$1" in
        ctrl)
          nodes_to_find=$ctrl_pattern
          echo "Execute Command on ctrl nodes"
          ;;
        comp)
          nodes_to_find=$comp_pattern
          echo "Execute Command on comp nodes"
          ;;
        net)
          nodes_to_find=$net_pattern
          echo "Execute Command on net nodes"
          ;;
        *)
          echo "type is not specified correctly. Execute Command on ctr, comp, net nodes"
          ;;
        esac
}

#======================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { COMMAND=$1; echo "Command parameter found with value $COMMAND"; }
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -c,   -command        <command>
      -nt,  -type_of_nodes  <type_of_nodes> 'ctrl', 'comp', 'net'
      -p,   -ping           ping before execution command
      Remove all containers on all nodes:
        bash command_on_nodes.sh -c 'docker stop $(docker ps -a -q)'
        bash command_on_nodes.sh -c 'docker system prune -af'
        bash command_on_nodes.sh -c 'docker volume prune -af'
"
        exit 0
        break ;;
    -c|-command) COMMAND="$2"
      echo "Found the -command <command> option, with parameter value $COMMAND"
      shift ;;
    -nt|-type_of_nodes)
      note_type_func "$2"
      shift ;;
    -p|-ping)
      PING="true"
      echo "Found the -ping option"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }
echo "${NODES[*]}"

check_connection () {
  for host in "${NODES[@]}"; do
    echo "host: $host"
    sleep 1
    if ping -c 2 $host &> /dev/null; then
        printf "%40s\n" "${green}There is a connection with $host - success${normal}"
    else
        printf "%40s\n" "${red}No connection with $IP - error!${normal}"
    fi
  done
}

start_commands_on_nodes () {
  for host in "${NODES[@]}"; do
    echo "Start command on ${host}"
    ssh -o StrictHostKeyChecking=no -t "$host" $COMMAND
#    ssh -o StrictHostKeyChecking=no -t $host << EOF
#$COMMAND
#EOF
  done
}

[ "$PING" = true ] && { check_connection; }
start_commands_on_nodes


