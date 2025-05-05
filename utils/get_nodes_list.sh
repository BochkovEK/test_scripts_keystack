#!/bin/bash

#The scrip get nodes list
# !!! ip and name nodes list needed in /etc/hosts


script_dir=$(dirname $0)
utils_dir=$script_dir
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"

comp_pattern="comp\-..(\s|$)"
#$"
ctrl_pattern="ctrl\-..(\s|$)"
#$"
net_pattern="net\-..(\s|$)"
#net_pattern="\-net\-.."
#$"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $NODES_TYPE ]] && NODES_TYPE=""
[[ -z $PING ]] && PING="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
#======================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { NODES_TYPE=$1; [ "$TS_DEBUG" = true ] && echo -e "Nodes type parameter found with value $NODES_TYPE"; }
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      ip and name nodes list needed in /etc/hosts

      -nt,  -type_of_nodes  <type_of_nodes> 'ctrl', 'comp', 'net'
      -debug               debug mode (without parameter)
"
        exit 0
        break ;;
    -debug) TS_DEBUG="true"
      [ "$TS_DEBUG" = true ] && echo -e "
      Found the -debug parameter
      "
      ;;
    -nt|-type_of_nodes) NODES_TYPE=$2
      [ "$TS_DEBUG" = true ] && echo -e "
      Found the -type_of_nodes with parameter value $NODES_TYPE
      "
      shift ;;
    --) shift
      break ;;
    *)
      [ "$TS_DEBUG" = true ] && echo -e "
      Parameter #$count: $1
      "
      define_parameters "$1"
      count=$(( $count + 1 ))
      ;;
  esac
  shift
done


node_type_func () {
  case "$1" in
        ctrl)
          NODES_TYPE=ctrl
          nodes_to_find=$ctrl_pattern
          [ "$TS_DEBUG" = true ] && echo -e "
          NODES_TYPE: $NODES_TYPE
          nodes_to_find: $nodes_to_find
          "
#          ${yellow}Execute command on ctrl nodes${normal}
          ;;
        comp|cmpt)
          NODES_TYPE=comp
          nodes_to_find=$comp_pattern
          [ "$TS_DEBUG" = true ] && echo -e "
          NODES_TYPE: $NODES_TYPE
          nodes_to_find: $nodes_to_find
          "
          ;;
        net)
          NODES_TYPE=net
          nodes_to_find=$net_pattern
          [ "$TS_DEBUG" = true ] && echo -e "
          NODES_TYPE: $NODES_TYPE
          nodes_to_find: $nodes_to_find
          "
          ;;
        *)
          NODES_TYPE=all
          nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"
          [ "$TS_DEBUG" = true ] && echo -e "
          NODES_TYPE: $NODES_TYPE
          nodes_to_find: $nodes_to_find
          "
#          ${yellow}Nodes type is not specified correctly. Execute command on ctr, comp, net nodes${normal}
          ;;
        esac
}

check_openstack_cli () {
#  echo "check"
  export DONT_ASK=true
  export DONT_INSTALL=true
  if bash $utils_dir/$check_openstack_cli_script &> /dev/null; then
#    pass
    check_and_source_openrc_file
#    get_list_from_compute_service
#    exit 0
  fi
}

check_and_source_openrc_file () {
#  echo "check openrc"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
#  if bash $utils_dir/$check_openrc_script 2>&1; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    exit 1
  fi
}

parse_hosts () {
  [ "$TS_DEBUG" = true ] && echo -e "
  Parse /etc/hosts to find pattern: $nodes_to_find
  "
#  node_type_func $NODES_TYPE
  [[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }
  if [ "$TS_DEBUG" = true ]; then
    echo -e "
    [DEBUG]
    NODES:
    "
    for host in "${NODES[@]}"; do
      [ "$TS_DEBUG" = true ] && echo -e "
      [DEBUG]
      host: $host
      "
    done
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]
    NODES_TYPE: $NODES_TYPE
    "
  fi
  echo "${NODES[*]}"
  if [ -z "${NODES[*]}" ]; then
    echo -e "${red}Failed to determine node $NODES_TYPE list - ERROR!${normal}"
    exit 1
  fi
}

get_list_from_compute_service () {
#    echo "get_list_from_compute_service..."
  if [ -z ${NODES[0]} ]; then
     [ "$TS_DEBUG" = true ] && echo -e "
        [DEBUG]
          NODES[0]: ${NODES[0]}
          "
    if [ "$NODES_TYPE" = comp ] || [ "$NODES_TYPE" = ctrl ]; then
      [ "$TS_DEBUG" = true ] && echo -e "
        [DEBUG]
          NODES_TYPE: $NODES_TYPE
          "
      nova_state_list=$(openstack compute service list)
      if [ -z "$nova_state_list" ];then
        [ "$TS_DEBUG" = true ] && echo -e "
        [DEBUG]
        ${yellow}Failed to determine node $NODES_TYPE list${normal}
        "
#        return
#        exit 1
      elif [ "$NODES_TYPE" = comp ]; then
        #compute
        nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)" | awk '{print $6}')
      else
        #control
        nodes=$(echo "$nova_state_list" | grep -E "(nova-scheduler)" | awk '{print $6}')
      fi
      if [[ -z $nodes ]];then
        [ "$TS_DEBUG" = true ] && echo -e "
        [DEBUG]
        ${yellow}Failed to determine node $NODES_TYPE list${normal}
        "
#        return
#        exit 1
        parse_hosts
      else
        echo $nodes
      fi
    elif [ "$NODES_TYPE" = all ]; then
      parse_hosts
    fi
  else
    return
  fi
}


node_type_func $NODES_TYPE
check_openstack_cli
#check_and_source_openrc_file
get_list_from_compute_service
#check_and_source_openrc_file
#parse_hosts
#get_list_from_compute_service



