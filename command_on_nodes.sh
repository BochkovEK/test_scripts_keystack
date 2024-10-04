#!/bin/bash

#The scrip starts command on nodes
# !!! ip and name nodes list needed in /etc/hosts

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

script_dir=$(dirname $0)
utils=$script_dir/utils

comp_pattern="\-comp\-.."
#$"
ctrl_pattern="\-ctrl\-.."
#$"
net_pattern="\-net\-.."
#$"



#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $COMMAND ]] && COMMAND="ls -la"
[[ -z $SENDENV ]] && SENDENV=""
[[ -z $NODES ]] && NODES=()
[[ -z $NODES_TYPE ]] && NODES_TYPE=""
[[ -z $PING ]] && PING="false"
[[ -z $DEBUG ]] && DEBUG="false"
#======================

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      ip and name nodes list needed in /etc/hosts

      -c,   -command        \"<command>\"
      -nt,  -type_of_nodes  <type_of_nodes> 'ctrl', 'comp', 'net'
      -p,   -ping           ping before execution command
      --debug               debug mode
      Remove all containers on all nodes:
        bash command_on_nodes.sh -c 'docker stop $(docker ps -a -q)'
        bash command_on_nodes.sh -c 'docker system prune -af'
        bash command_on_nodes.sh -c 'docker volume prune -af'
"
#      -e,   -send_env       \"<ENV_NAME=env_value>\"
        exit 0
        break ;;
    -c|-command) COMMAND="$2"
      echo "Found the -command \"<command>\" option, with parameter value $COMMAND"
      shift ;;
#    -e|-send_env)
#      SENDENV_NAME=${2%=*}
#      $2
#      SENDENV=$SENDENV"-o \"SendEnv $SENDENV_NAME\""
#      echo "Found the -send_env \"<ENV_NAME=env_value>\" option, with parameter value $2"
#      echo "SENDENV: $SENDENV"
#      shift ;;
    -nt|-type_of_nodes)
      note_type_func "$2"
      shift ;;
    -p|-ping)
      PING="true"
      echo "Found the -ping option"
      ;;
    --debug)
      DEBUG="true"
      echo "Found the --debug parameter"
      shift ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

note_type_func () {
  case "$1" in
        ctrl)
          NODES_TYPE=ctrl
          nodes_to_find=$ctrl_pattern
          printf "%s\n" "${yellow}Execute command \'$COMMAND\' on ctrl nodes${normal}"
          ;;
        comp)
          NODES_TYPE=comp
          nodes_to_find=$comp_pattern
          printf "%s\n" "${yellow}Execute command \'$COMMAND\' on comp nodes${normal}"
          ;;
        net)
          NODES_TYPE=net
          nodes_to_find=$net_pattern
          printf "%s\n" "${yellow}Execute command \'$COMMAND\' on net nodes${normal}"
          ;;
        *)
          NODES_TYPE=all
          nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"
          printf "%s\n" "${yellow}Nodes type is not specified correctly. Execute command \'$COMMAND\' on ctr, comp, net nodes${normal}"
          ;;
        esac
}

error_output () {
  printf "%s\n" "${yellow}command not executed on $NODES_TYPE nodes${normal}"
  printf "%s\n" "${red}$error_message - error${normal}"
  exit 1
}

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { COMMAND=$1; echo "Command parameter found with value $COMMAND"; }
}

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
  if [ "$DEBUG" = true ]; then
    echo -e "
  [DEBUG]
  NODES:
    "
    for host in "${NODES[@]}"; do
      echo $host
    done
  fi
  if [[ -z ${NODES[0]} ]]; then
    error_message="Failed to access to $NODES_TYPE"
    error_output
    exit 1
  fi
  for host in "${NODES[@]}"; do
    echo -E "${yellow}Start command on ${host}${normal}"
    ssh -o StrictHostKeyChecking=no -t $SENDENV "$host" ${COMMAND}
#    ssh -o StrictHostKeyChecking=no -t $host << EOF
#$COMMAND
#EOF
  done
}

yes_no_answer () {
  yes_no_input=""
  while true; do
    read -p "$yes_no_question" yn
    yn=${yn:-"Yes"}
    echo $yn
    case $yn in
        [Yy]* ) yes_no_input="true"; break;;
        [Nn]* ) yes_no_input="false"; break ;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  yes_no_question="<Empty yes\no question>"
}

#check_openstack_cli
check_openstack_cli () {
  if ! bash $utils/check_openstack_cli.sh; then
#    error_message="Failed to check openstack"
#    error_output
    exit 1
  fi
}

check_and_source_openrc_file () {
  echo "check openrc"
  if ! bash $utils/openrc.sh; then
    exit 1
  else
    echo $OPENRC_PATH
  fi
}

check_ping () {
  if ping -c 2 $1 &> /dev/null; then
      printf "%40s\n" "${green}There is a connection with $1 - success${normal}"
  else
    connection_problem="true"
    printf "%40s\n" "${red}No connection with $1${normal}"
  fi
  NODES+=("$1")
  sleep 1
}

get_list_from_compute_service () {
  check_openstack_cli
  check_and_source_openrc_file
  nova_state_list=$(openstack compute service list)
  if [ -z $nova_state_list ];then
    error_message="Failed to determine node $NODES_TYPE list"
    error_output
    exit 1
  else
    if  [ "$NODES_TYPE" = comp ]; then
      #compute
      nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)" | awk '{print $6}')
    else
      #control
      nodes=$(echo "$nova_state_list" | grep -E "(nova-scheduler)" | awk '{print $6}')
    fi
    if [ -z $nodes ];then
      error_message="Failed to determine node $NODES_TYPE list"
      error_output
      exit 1
    fi
  fi
  echo "Check connection to $NODES_TYPE"
  for node in $nodes; do
    check_ping $node
  done
  if [ "$connection_problem" = true ]; then
    error_message="Could not connection to $node"
    error_output
  fi
}


echo "Parse /etc/hosts to find pattern: $nodes_to_find"
[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }
if [ "$DEBUG" = true ]; then
  echo -e "
  [DEBUG]
  NODES:
  "
  for host in "${NODES[@]}"; do
    echo $host
  done
  echo "NODES_TYPE: $NODES_TYPE"
fi
if [ -z ${NODES[0]} ]; then
  if [ "$NODES_TYPE" = comp ] || [ "$NODES_TYPE" = ctrl ]; then
    yes_no_question="Do you want to try to compute service list to define $NODES_TYPE list [Yes]: "
    yes_no_answer
    if [ "$yes_no_input" = "true" ]; then
      get_list_from_compute_service
    else
      error_message="Pattern: $nodes_to_find could not be found in /etc/hosts"
      error_output
    fi
  else
    error_message="Pattern: $nodes_to_find could not be found in /etc/hosts"
    error_output
  fi
fi

start_commands_on_nodes
