#!/bin/bash

#The scrip get nodes list
# !!! ip and name nodes list needed in /etc/hosts


script_dir=$(dirname $0)
utils_dir=$script_dir
check_openrc_script="check_openrc.sh"
default_hosts_path="/etc/hosts"
check_openstack_cli_script="check_openstack_cli.sh"

comp_pattern="comp\-..(\s|$)"
#$"
ctrl_pattern="ctrl\-..(\s|$)"
#$"
net_pattern="net\-..(\s|$)"
comp_compute_service_pattern="(nova-compute)"
ctrl_compute_service_pattern="(nova-scheduler)"
#net_pattern="\-net\-.."
#$"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $PING ]] && PING="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $TS_HOSTS_PATH ]] && TS_HOSTS_PATH=$default_hosts_path
#[[ -z $WITHOUT_NETWORK_NODES ]] && WITHOUT_NETWORK_NODES="false"

#======================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { NODES_TYPE=$1; [ "$TS_DEBUG" = true ] && echo -e "Nodes type parameter found with value $NODES_TYPE"; }
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      ip and name nodes list needed in 'hosts' file (define by -h key, or by env TS_HOSTS_PATH; hosts path by default: $default_hosts_path)

      -nt,  -type_of_nodes          <type_of_nodes> 'ctrl', 'comp', 'net', 'all', 'all_without_network\awn'
      -h,   -hosts_path             <path_to_hosts_file>
      -debug                        debug mode (without parameter)
"
#      -wnn, -without_network_nodes  if the region does not have a network node (without parameter)
        exit 0
        break ;;
    -debug) TS_DEBUG="true"
      [ "$TS_DEBUG" = true ] && echo -e "
      Found the -debug parameter
      "
      ;;
#    -wnn|-without_network_nodes) NODES_TYPE=$2
#      [ "$TS_DEBUG" = true ] && echo -e "
#      Found the -without_network_nodes with parameter value $WITHOUT_NETWORK_NODES
#      "
#      ;;
    -nt|-type_of_nodes) NODES_TYPE=$2
      [ "$TS_DEBUG" = true ] && echo -e "
      Found the -type_of_nodes with parameter value $NODES_TYPE
      "
      shift ;;
    -nn|-nodes_name) NODES_NAME=$2
      [ "$TS_DEBUG" = true ] && echo -e "
      Found the -nodes_name with parameter value $NODES_NAME
      "
      shift ;;
    -h|-hosts_path) TS_HOSTS_PATH=$2
      [ "$TS_DEBUG" = true ] && echo -e "
      Found the -hosts_path with parameter value $TS_HOSTS_PATH
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
#  else
#    bash $utils_dir/$check_openrc_script
#    exit 1
  fi
}

# Function to find IP in hosts file
find_in_hosts_file() {
    local hostname=$1
    [ -f "$TS_HOSTS_PATH" ] || echo baz
    #return 1
    echo "bar"
    grep -w "$hostname" "$TS_HOSTS_PATH" | awk '{print $1}' | head -n1
}

resolve_hostname_to_ips () {
    # Resolve hostnames to IPs
    echo "foo"
    for i in "${!NODES[@]}"; do
        local host="${NODES[$i]}"
        local ip=$(dig +short "$host" 2>/dev/null | head -n1)

        if [ -z "$ip" ]; then
            ip=$(find_in_hosts_file "$host")
        fi

        if [ -n "$ip" ]; then
            NODES[$i]="$ip"
        else
            echo "Warning: failed to resolve $host" >&2
            NODES[$i]="unresolved:$host"
        fi
    done
}

# Main function to parse hosts and resolve to IP
parse_hosts() {
    [ "$TS_DEBUG" = true ] && echo "Parsing $TS_HOSTS_PATH for pattern: $nodes_to_find"

    # Populate NODES array if empty
    if [ ${#NODES[@]} -eq 0 ]; then
        while read -r line; do
            NODES+=("$line")
        done < <(grep -E "$nodes_to_find" "$TS_HOSTS_PATH" | awk '{print $2}')
    fi

    # Debug output
    [ "$TS_DEBUG" = true ] && printf "NODES: %s\n" "${NODES[*]}"

    resolve_hostname_to_ips

    echo "${NODES[*]}"

    # Check if we have any valid nodes
    if [ ${#NODES[@]} -eq 0 ]; then
        echo "Failed to determine node list from $TS_HOSTS_PATH" >&2
        exit 1
    fi
}

get_list_from_compute_service () {
  nova_state_list=$(openstack compute service list)
  if [ -z "$nova_state_list" ];then
   [ "$TS_DEBUG" = true ] && echo -e "
[DEBUG]
${yellow}Failed - openstack compute service is empty${normal}
   "
    parse_hosts
  else
    nodes=$(echo "$nova_state_list" | grep -E $grep_from_compute_service | awk '{print $6}')
    if [[ -z $nodes ]];then
      [ "$TS_DEBUG" = true ] && echo -e "
      [DEBUG]
      ${yellow}Failed to find $grep_from_compute_service in compute service list${normal}
      "
    else
      echo $nodes
    fi
  fi
}

define_node_type () {
  case "$1" in
    ctrl)
      NODES_TYPE=ctrl
      nodes_to_find=$ctrl_pattern
      grep_from_compute_service=$ctrl_compute_service_pattern
      [ "$TS_DEBUG" = true ] && echo -e "
NODES_TYPE: $NODES_TYPE
nodes_to_find: $nodes_to_find
      "
#      get_list_from_compute_service
      parse_hosts
      ;;
    comp|cmpt)
      NODES_TYPE=comp
      nodes_to_find=$comp_pattern
      grep_from_compute_service=$comp_compute_service_pattern
      [ "$TS_DEBUG" = true ] && echo -e "
NODES_TYPE: $NODES_TYPE
nodes_to_find: $nodes_to_find
      "
#      get_list_from_compute_service
      parse_hosts
      ;;
    awn|all_without_network)
      NODES_TYPE=all_without_network
      nodes_to_find="$comp_pattern|$ctrl_pattern"
      grep_from_compute_service="$comp_compute_service_pattern|$ctrl_compute_service_pattern"
      [ "$TS_DEBUG" = true ] && echo -e "
NODES_TYPE: $NODES_TYPE
nodes_to_find: $nodes_to_find
      "
#      get_list_from_compute_service
      parse_hosts
      ;;
    net)
      NODES_TYPE=net
      nodes_to_find=$net_pattern
      [ "$TS_DEBUG" = true ] && echo -e "
NODES_TYPE: $NODES_TYPE
nodes_to_find: $nodes_to_find
      "
#      coming soon: openstack network agent list
      parse_hosts
      ;;
    all)
      NODES_TYPE=all
      nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"
      [ "$TS_DEBUG" = true ] && echo -e "
      NODES_TYPE: $NODES_TYPE
      nodes_to_find: $nodes_to_find
      "
      parse_hosts
      ;;
    *)
      [ "$TS_DEBUG" = true ] && echo -e "${red}Node type \'$2\' could not be determined, run script with --help - ERROR${normal}"
      exit 1
      ;;
  esac
}


check_and_source_openrc_file
if [ -n "$NODES_NAME" ]; then
  echo "i am here"
  for hostname in $NODES_NAME; do
    NODES+=("$hosname")
  done
  resolve_hostname_to_ips
  exit 0
fi
define_node_type $NODES_TYPE
#node_type_func
#check_openstack_cli



