#!/bin/bash

#The scrip starts command on nodes
# !!! ip and name nodes list needed in /etc/hosts

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
get_nodes_list_script="get_nodes_list.sh"

#comp_pattern="\-comp\-.."
##$"
#ctrl_pattern="\-ctrl\-.."
##$"
#net_pattern="\-net\-.."
##$"

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
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
#======================

#node_type_func () {
#  case "$1" in
#        ctrl)
#          NODES_TYPE=ctrl
#          nodes_to_find=$ctrl_pattern
#          printf "%s\n" "${yellow}Execute command on ctrl nodes${normal}"
#          ;;
#        comp)
#          NODES_TYPE=comp
#          nodes_to_find=$comp_pattern
#          printf "%s\n" "${yellow}Execute command on comp nodes${normal}"
#          ;;
#        net)
#          NODES_TYPE=net
#          nodes_to_find=$net_pattern
#          printf "%s\n" "${yellow}Execute command on net nodes${normal}"
#          ;;
#        *)
#          NODES_TYPE=all
#          nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"
#          printf "%s\n" "${yellow}Nodes type is not specified correctly. Execute command on ctr, comp, net nodes${normal}"
#          ;;
#        esac
#}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      ip and name nodes list needed in /etc/hosts

      -c,   -command        \"<command>\"
      -nt,  -type_of_nodes  <type_of_nodes> 'ctrl', 'comp', 'net'
      -nn,  -node_name      <node_name\ip> example: -nn \"ebochkov-keystack-comp-01 ebochkov-keystack-comp-02\"
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
    -nt|-type_of_nodes) NODES_TYPE=$2
      echo "Found the -type_of_nodes, with parameter value $NODES_TYPE"
      shift ;;
    -nn|-node_name)
      for i in $2; do NODES+=("$i"); done
      echo "Found the -nn option, with parameter value ${NODES[*]}"
      shift ;;
    -p|-ping)
      PING="true"
      echo "Found the -ping option"
      ;;
    -debug) TS_DEBUG="true"
      echo "Found the -debug parameter"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done


error_output () {
  printf "%s\n" "${yellow}Command not executed on $NODES_TYPE nodes${normal}"
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

##check_openstack_cli
#check_openstack_cli () {
#  if ! bash $utils_dir/check_openstack_cli.sh; then
##    error_message="Failed to check openstack"
##    error_output
#    exit 1
#  fi
#}
#
#check_and_source_openrc_file () {
#  echo "check openrc"
#  openrc_file=$(bash $utils_dir/check_openrc.sh)
#  if [[ -z $openrc_file ]]; then
#    exit 1
#  else
#    echo $openrc_file
#    source $openrc_file
#  fi
#}

check_ping () {
  if ping -c 2 $1 &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $1 - success${normal}"
#    NODES+=("$1")
    sleep 1
  else
    connection_problem="true"
    printf "%40s\n" "${red}No connection with $1${normal}"
#    problems_nodes+=("$1")
  fi

}

#get_list_from_compute_service () {
#  check_openstack_cli
#  check_and_source_openrc_file
#  nova_state_list=$(openstack compute service list)
#  if [[ -z $nova_state_list ]];then
#    error_message="Failed to determine node $NODES_TYPE list"
#    error_output
#    exit 1
#  else
#    if  [ "$NODES_TYPE" = comp ]; then
#      #compute
#      nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)" | awk '{print $6}')
#    else
#      #control
#      nodes=$(echo "$nova_state_list" | grep -E "(nova-scheduler)" | awk '{print $6}')
#    fi
#    echo "nodes: $nodes"
#    if [[ -z $nodes ]];then
#      error_message="Failed to determine node $NODES_TYPE list"
#      error_output
#      exit 1
#    fi
#  fi
#  echo "Check connection to $NODES_TYPE"
#  for node in $nodes; do
#    check_ping $node
#  done
#
#}


#echo "Parse /etc/hosts to find pattern: $nodes_to_find"
#[[ -z ${NODES[0]} ]] && {
#  node_type_func $NODES_TYPE
#  srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}');
#  for i in $srv; do NODES+=("$i"); done; }
#if [ "$DEBUG" = true ]; then
#  echo -e "
#  [DEBUG]
#  NODES:
#  "
#  for host in "${NODES[@]}"; do
#    echo $host
#  done
#  echo "NODES_TYPE: $NODES_TYPE"
#fi
#
#if [ -z ${NODES[0]} ]; then
#  if [ "$NODES_TYPE" = comp ] || [ "$NODES_TYPE" = ctrl ]; then
#    yes_no_question="Do you want to try to compute service list to define $NODES_TYPE list [Yes]: "
#    yes_no_answer
#    if [ "$yes_no_input" = "true" ]; then
#      get_list_from_compute_service
#    else
#      error_message="Pattern: $nodes_to_find could not be found in /etc/hosts"
#      error_output
#    fi
#  else
#    error_message="Pattern: $nodes_to_find could not be found in /etc/hosts"
#    error_output
#  fi
#fi

get_nodes_list () {
  if [ -z "${NODES[*]}" ]; then
    nodes=$(bash $utils_dir/$get_nodes_list_script -nt $NODES_TYPE)
  fi
  if echo $nodes| grep "ERROR"; then
#    echo -e "$nodes"
    exit 1
  fi
#  node=$(cat /etc/hosts | grep -m 1 -E ${nodes_pattern} | awk '{print $2}')
#  [ "$TS_DEBUG" = true ] && echo -e "
#  [DEBUG]: \"\$node\": $node\n
#  "
  for node in $nodes; do NODES+=("$node"); done
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$NODES\": ${NODES[*]}
  "
  echo -e "
  NODES: ${NODES[*]}
  "
  if [ -z "${NODES[*]}" ]; then
    echo -e "${red}Failed to determine node list - ERROR${normal}"
    exit 1
  fi
}

get_nodes_list

echo "Check connection to $NODES_TYPE"
for node in "${NODES[@]}"; do
  check_ping $node
done

if [ "$connection_problem" = true ]; then
  yes_no_question="Do you want to run a command on nodes without connection problems? [Yes]: "
  yes_no_answer
  if [ "$yes_no_input" = "true" ]; then
    start_commands_on_nodes
  else
    error_message="Command failed. Some nodes have connection problems"
    error_output
  fi
else
  start_commands_on_nodes
fi


