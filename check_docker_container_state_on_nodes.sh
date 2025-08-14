#!/bin/bash

#The scrip check container state on nodes or node

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

#comp_pattern="\-comp\-..($|\s)"
#ctrl_pattern="\-ctrl\-..($|\s)"
#net_pattern="\-net\-..($|\s)"
#nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

script_dir=$(dirname $0)
script_name=$(basename "$0")
utils_dir=$script_dir/utils
get_nodes_list_script="get_nodes_list.sh"
default_ssh_user="root"
default_docker_engine="docker"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
magenta=$(tput setaf 200)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 6)

ctrl_required_container_list=(
  "keystone"
  "keystone_ssh"
  "rabbitmq"
  "memcached"
  "mariadb"
  "redis"
  "haproxy"
  "horizon"
  "nova_serialproxy"
  "nova_novncproxy"
  "nova_conductor"
  "nova_api"
  "nova_scheduler"
  "placement_api"
  "cinder_volume"
  "cinder_scheduler"
  "cinder_api"
  "adminui_frontend"
  "adminui_backend"
  "drs"
  "consul"
  "prometheus_consul_exporter"
  "prometheus_blackbox_exporter"
  "prometheus_elasticsearch_exporter"
  "prometheus_openstack_exporter"
  "prometheus_alertmanager"
  "prometheus_memcached_exporter"
  "prometheus_rabbitmq_exporter"
  "prometheus_mysqld_exporter"
  "prometheus_node_exporter"
  "prometheus_server"
)

comp_required_container_list=(
  "iscsid"
  "consul"
  "neutron_openvswitch_agent"
  "openvswitch_vswitchd"
  "openvswitch_db"
  "nova_compute"
  "nova_libvirt"
  "nova_ssh"
  "prometheus_hypervisor_exporter"
  "prometheus_ovs_exporter"
  "prometheus_libvirt_exporter"
  "prometheus_node_exporter"
  "prometheus_blackbox_exporter"
  "cron"
  "fluentd"
)
# inventory
#   [monitoring:children]
#   control
#   [prometheus-blackbox-exporter:children]
#   monitoring
# "prometheus_blackbox_exporter" not required on comp

#required_container_list=()

[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME=""
[[ -z $NODES ]] && NODES=()
[[ -z $CHECK_UNHEALTHY ]] && CHECK_UNHEALTHY="false"
[[ -z $NODES_TYPE ]] && NODES_TYPE=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $DOCKER_ENGINE ]] && DOCKER_ENGINE=$default_docker_engine
#[[ -z $SSH_USER ]] && SSH_USER=$default_ssh_user # !!! replaced by the logic described below
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
      -nt, 	-type_of_nodes		<type_of_nodes>: 'all', 'ctrl', 'comp', 'net', 'all_without_network\awn'
      -nn,  -node_name        <nodes_name_list> (exp: -nn \"cdm-bl-pca06 cdm-bl-pca07\")
      -check_unhealthy        check only unhealthy containers (without parameter)
      -u,   -user             <ssh_user>
      -de,  -docker_engine    <docker_engine: docker\podman>
      -debug                  enable debug output (without parameter)
"
      exit 0
      break
      ;;
	  -c|-container_name) CONTAINER_NAME="$2"
	    echo "Found the -container_name <container_name> option, with parameter value $CONTAINER_NAME"
      shift
      ;;
    -nt|-type_of_nodes) NODES_TYPE=$2
      echo "Found the -type_of_nodes  with parameter value $NODES_TYPE"
#      note_type_func "$2"
      shift
      ;;
    -nn|-node_name) NODE_NAME=$2
      echo "Found the -node_name  with parameter value $NODE_NAME"
#      note_type_func "$2"
      shift
      ;;
    -de|-docker_engine) DOCKER_ENGINE=$2
      echo "Found the -docker_engine with parameter value $DOCKER_ENGINE"
      shift
      ;;
    -u|-user) SSH_USER=$2
      echo "Found the -user with parameter value $SSH_USER"
      shift
      ;;
    -check_unhealthy) CHECK_UNHEALTHY="true"
      echo "Found the -check_unhealthy  with parameter value $CHECK_UNHEALTHY"
      ;;
    -debug) TS_DEBUG="true"
      echo "Found the -debug with parameter value $TS_DEBUG"
      ;;
    --) shift
      break
      ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done


check_required_container () {
  echo -e "Check required container on $1"
#  container_name_on_node=$(ssh -o StrictHostKeyChecking=no $SSH_USER@$1 'sudo \$DOCKER_ENGINE ps --format "{{.Names}}" --filter status=running')
#  container_name_on_node=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$1" "sudo \$DOCKER_ENGINE ps --format '{{.Names}}' --filter status=running")
  container_name_on_node=$(ssh -o StrictHostKeyChecking=no -t $SSH_USER@$1 "sudo $DOCKER_ENGINE ps --format '{{.Names}}' --filter status=running")
#  echo $container_name_on_node
  for container_requaired in "${required_containers_list[@]}"; do
    container_exist="false"
    for container in $container_name_on_node; do
      [ "$TS_DEBUG" = true ] && echo -e "
[DEBUG]:  container_name:      $container
          container_requaired: $container_requaired
"
      if [ "$container" = "$container_requaired" ]; then
        container_exist="true"
      fi
    done
    if [ "$container_exist" = "true" ]; then
      container_exist="true"
    else
      echo -e "${red}Container $container_requaired not running - ERROR${normal}"
    fi
  done
}

get_nodes_list () {
  if [ -z "${NODES[*]}" ]; then
    nodes=$(bash $utils_dir/$get_nodes_list_script -nt $NODES_TYPE)
  fi
#  node=$(cat /etc/hosts | grep -m 1 -E ${nodes_pattern} | awk '{print $2}')
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$node\": $node\n
  "
  for node in $nodes; do NODES+=("$node"); done
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$NODES\": ${NODES[*]}
  "
  #check error
  for word in "${NODES[@]}"; do
    [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    word in NODES: $word
  "
    error_in_NODES=$(echo $word|grep "ERROR")
    if [ -n "$error_in_NODES" ]; then
      echo -e "${yellow}Node names could not be determined.
        Try:
          bash ~/test_scripts_keystack/utils/get_nodes_list.sh -nt all
          or
          bash $script_dir/$script_name -nn \"<space-separated_list_of_hostnames>\"${normal}"
      echo -e "${red}Node names could not be determined - ERROR!${normal}"
      exit 1
    fi
  done
  if [ -z "${NODES[*]}" ]; then
    echo -e "${red}Failed to determine node list - ERROR!${normal}"
    exit 1
  fi
}


if [[ -z "$SSH_USER" ]]; then
  # Try to determine via whoami (with error handling)
  SSH_USER=$(whoami 2>/dev/null) || {
    echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
    # Use default value
    SSH_USER="$default_ssh_user"
  }
fi

# Final value check
if [[ -z "$SSH_USER" ]]; then
  echo -e "${red}Error: Failed to determine user!${normal}" >&2
  exit 1
fi

if [ -z "$NODE_NAME" ]; then
  get_nodes_list
else
  for word in $NODE_NAME; do
    NODES+=("$word")
  done
#  NODES=("$NODE_NAME")
fi

[[ "$CHECK_UNHEALTHY" = true  ]] && {
  UNHEALTHY="\(unhealthy\)";
  echo "UNHEALTHY: $UNHEALTHY";
  }

#grep_string="| grep -E \"$UNHEALTHY\\s+$CONTAINER_NAME\""
#grep_string="| grep -E $CONTAINER_NAME"

[ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  CONTAINER_NAME: $CONTAINER_NAME
  grep_string: $grep_string
  "

for host in "${NODES[@]}"; do
  if [ -z $CONTAINER_NAME ]; then
    echo -e "${cyan}Check containers on ${host}${normal}"
  else
    echo "Check container (CONTAINER_NAME: $CONTAINER_NAME) on ${host}"
    grep_string="|grep $CONTAINER_NAME"
  fi
  status=$(ssh -o "StrictHostKeyChecking=no" -o BatchMode=yes -o ConnectTimeout=5 $SSH_USER@$host echo ok 2>&1)

  if [[ $status == ok ]] ; then

#  if ping -c 2 $host &> /dev/null; then
    printf "%40s\n" "There is a connection with $host - ok!"

#    ssh -o StrictHostKeyChecking=no $host docker ps $grep_string \
    ssh -o StrictHostKeyChecking=no $SSH_USER@$host "sudo $DOCKER_ENGINE ps -a $grep_string \
      |sed --unbuffered \
        -e 's/\(.*(unhealthy).*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*Exited.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*second.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*Less than.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*(healthy).*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*days.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*About an hour.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*minutes.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*weeks.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*hours.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*starting).*\)/\o033[33m\1\o033[39m/'\
        -e 's/\(.*restarting.*\)/\o033[31m\1\o033[39m/'
        "

    is_ctrl=$(echo $host|grep ctrl)
    if [ -n "$is_ctrl" ]; then
      if [ -z $CONTAINER_NAME ]; then
        required_containers_list=( "${ctrl_required_container_list[@]}" )
        check_required_container $host
      fi
    fi
    is_comp=$(echo $host|grep -E "comp|cmpt")
    if [ -n "$is_comp" ]; then
      if [ -z $CONTAINER_NAME ]; then
        required_containers_list=( "${comp_required_container_list[@]}" )
        check_required_container $host
      fi
    fi
  elif [[ $status == *"Permission denied"* ]] ; then
    echo -e "${red}Error: ${normal}"
    echo -e "${red}\t${status}${normal}"
  else
    printf "%40s\n" "${red}No connection with $host - error!${normal}"
    echo -e "${red}The node may be turned off.${normal}\n"
  fi
done
