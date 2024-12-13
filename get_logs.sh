#!/bin/bash

# Script for get DRS logs

# On client OS:
# scp root@<lcm_ip>:~/test_scripts_keystack/drs-*.gz .

# unpacking: tar -xvzf drs-logs-08-04-2024.tar.gz -C ./

#cleanup on drs_logs folder: rm -f drs*.txt drs*.log migration.list optimization.list recommendation.list

#Colors
#green=$(tput setaf 2)
red=$(tput setaf 1)
#violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
get_nodes_list_script="get_nodes_list.sh"
install_package_script="install_package.sh"
drs_logs_dest_folder_name="drs_logs"
drs_container_name="drs"
consul_logs_dest_folder_name="consul_logs"
consul_container_name="consul"
scheduler_logs_dest_folder_name="nova_scheduler_logs"
scheduler_container_name="nova_scheduler"
nova_compute_logs_dest_folder_name="nova_compute_logs"
nova_compute_container_name="nova_compute"
nova_logs_folder_name="nova_logs"

[[ -z $TAIL_NUM ]] && TAIL_NUM=100
[[ -z $NODES_TYPE ]] && NODES_TYPE=""
#[[ -z $NODES_TO_FIND ]] && NODES_TO_FIND="ctrl"
# ---------
[[ -z $DRS_LOGS_SRC ]] && DRS_LOGS_SRC=/var/log/kolla/drs/drs.log
[[ -z $DRS_LOGS_DEST ]] && DRS_LOGS_DEST=$script_dir/$drs_logs_dest_folder_name
[[ -z $DRS_CONF_SRC ]] && DRS_CONF_SRC=/etc/kolla/drs
# ---------
[[ -z $CONSUL_LOGS_SRC ]] && CONSUL_LOGS_SRC=/var/log/kolla/autoevacuate.log
[[ -z $CONSUL_LOGS_DEST ]] && CONSUL_LOGS_DEST=$script_dir/$consul_logs_dest_folder_name
[[ -z $CONSUL_CONF_SRC ]] && CONSUL_CONF_SRC=/etc/kolla/consul
# ---------
[[ -z $NOVA_SCHEDULER_LOGS_SRC ]] && NOVA_SCHEDULER_LOGS_SRC=/var/log/kolla/nova/nova-scheduler.log
[[ -z $NOVA_SCHEDULER_LOGS_DEST ]] && NOVA_SCHEDULER_LOGS_DEST=$script_dir/$scheduler_logs_dest_folder_name
[[ -z $NOVA_SCHEDULER_CONF_SRC ]] && NOVA_SCHEDULER_CONF_SRC=/etc/kolla/nova-scheduler
# ---------
[[ -z $NOVA_COMPUTE_LOGS_SRC ]] && NOVA_COMPUTE_LOGS_SRC=/var/log/kolla/nova/nova-compute.log
[[ -z $NOVA_COMPUTE_LOGS_DEST ]] && NOVA_COMPUTE_LOGS_DEST=$script_dir/$nova_compute_logs_dest_folder_name
[[ -z $NOVA_COMPUTE_CONF_SRC ]] && NOVA_COMPUTE_CONF_SRC=/etc/kolla/nova-compute
# ---------
[[ -z $NOVA_LOGS_DEST ]] && NOVA_LOGS_DEST=$script_dir/$nova_logs_folder_name
#----------
[[ -z $LOGS_TYPE ]] && LOGS_TYPE=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"


while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      -l,     -logs              <logs_type> 'drs', 'ha', 'nova'
      "
      exit 0
      break ;;
  -l|-logs) LOGS_TYPE="$2"
	  echo "Found the -logs <logs_type>, with parameter value $LOGS_TYPE"
    shift ;;
  -debug) TS_DEBUG="true"
    echo "Found the -debug, with parameter value $TS_DEBUG"
    ;;
  --) shift
    break ;;
  *) echo "$1 is not an option";;
    esac
    shift
done

#check_host_command () {
#  if ! bash $utils_dir/$install_package_script host; then
#    echo -e "${red}Failed to check 'host' command - ERROR${normal}"
#    exit 1
#  fi
#}

add_to_archive () {
  echo -e "${yellow}Add logs to archive... $1-logs-"`date +"%d-%m-%Y"`"${normal}"
  [ -e $script_dir/$archive_logs_name.tar.gz ] && rm $script_dir/$archive_logs_name.tar.gz
  archive_logs_name=$(echo $1-logs-"`date +"%d-%m-%Y"`")
  echo "tar -czvf $script_dir/$archive_logs_name.tar.gz $2"
  tar -czvf $script_dir/$archive_logs_name.tar.gz $2
}

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

# args: service_name, src, dest, node_type, container_name
# exp: get_logs consul $CONSUL_CONF_SRC $CONSUL_LOGS_DEST ctrl consul
get_logs () {
  NODES_TYPE=$4
  echo -e "${yellow}Get $1 logs from $NODES_TYPE...${normal}"
  NODES=()
  get_nodes_list
  mkdir -p $2
  echo "destination $1 logs: $3"
  for node in "${NODES[@]}"; do
    host_name=$node
    if [ "$TS_DEBUG" = true ]; then
      echo "node: $node"
    fi
    echo "Copy $1 logs from $host_name..."
    if [ "$TS_DEBUG" = true ]; then
      echo "Source logs: $2"
      echo "Destination logs: $3"
      read -p "Press enter to continue: "
    fi
    scp -o "StrictHostKeyChecking=no" $node:$2 $3/${host_name}_${1}.log
    if [ "$TS_DEBUG" = true ]; then
      echo "Copy $1 logs tail: ${TAIL_NUM} from $host_name..."
      read -p "Press enter to continue: "
	  fi
	  tail_strings=$(ssh -o "StrictHostKeyChecking=no" $node tail -n $TAIL_NUM $2)
	  echo $tail_strings > $2/${host_name}_${1}_tail_${TAIL_NUM}.txt
	  if [ "$TS_DEBUG" = true ]; then
	    echo "Copy docker logs $1 from $host_name..."
	    read -p "Press enter to continue: "
	  fi
	  ssh -o "StrictHostKeyChecking=no" $node "docker logs $5 2>&1 | tee /tmp/docker_logs_${1}.txt" &> /dev/null
    scp -o "StrictHostKeyChecking=no" $node:/tmp/docker_logs_${1}.txt $3/docker_logs_${1}_from_${host_name}.txt
	  if [ "$TS_DEBUG" = true ]; then
	    echo "Copy docker inspect $1 from $host_name..."
	    read -p "Press enter to continue: "
	  fi
	  docker_inspect_strings=$(ssh -o "StrictHostKeyChecking=no" $node docker inspect $5)
	  echo $docker_inspect_strings > $3/docker_inspect_${1}_from_${host_name}.txt
  done
}

#get_drs_logs () {
#  NODES_TYPE="ctrl"
#  get_nodes_list
#  mkdir -p $DRS_LOGS_DEST
##  ABSOLUTE_DRS_LOGS_DEST=$(realpath $DRS_LOGS_DEST)
#  echo "destination drs logs: $DRS_LOGS_DEST"
##  srv=$(cat /etc/hosts | grep -E ${NODES_TO_FIND} | awk '{print $2}')
##  [[ -z "${srv}" ]] && {
##    printf "%s\n" "${red}It was not possible to separate the names and addresses of control nodes from the hosts file - error!${normal}";
##    #echo "It was not possible to separate the names and addresses of control nodes from the hosts file";
##    exit 1;
##    }
#  for node in "${NODES[@]}"; do
##	  host_name=$(cat /etc/hosts | grep -E ${node} | awk '{print $2}')
##    [[ -z $host_name ]] && { host_name=$node; }
#    host_name=$node
##    echo $node
#    echo "Copy drs logs from $host_name..."
#    echo "DRS_LOGS_SRC: $DRS_LOGS_SRC"
#    read -p "Press enter to continue: "
#    scp -o "StrictHostKeyChecking=no" $node:$DRS_LOGS_SRC $DRS_LOGS_DEST/drs_log_from_$host_name.log
#    echo "Copy drs logs tail: ${TAIL_NUM} from $host_name..."
#     read -p "Press enter to continue: "
#	  tail_strings=$(ssh -o "StrictHostKeyChecking=no" $node tail -n $TAIL_NUM $DRS_LOGS_SRC)
#	  echo $tail_strings > $DRS_LOGS_DEST/drs_log_from_${host_name}_tail_${TAIL_NUM}.txt
#	  echo "Copy docker logs drs from $host_name..."
#	   read -p "Press enter to continue: "
#	  ssh -o "StrictHostKeyChecking=no" $node "docker logs drs 2>&1 | tee /tmp/docker_logs_drs.txt" &> /dev/null
##	  ssh -t -o "StrictHostKeyChecking=no" $node docker logs drs > /tmp/docker_logs_drs.txt #&> /dev/null)
##	  echo $docker_logs_drs_strings > $DRS_LOGS_DEST/docker_logs_drs_from_${host_name}.txt
#    scp -o "StrictHostKeyChecking=no" $node:/tmp/docker_logs_drs.txt $DRS_LOGS_DEST/docker_logs_drs_from_${host_name}.txt
#	  echo "Copy docker inspect drs from $host_name..."
#	   read -p "Press enter to continue: "
#	  docker_inspect_drs_strings=$(ssh -o "StrictHostKeyChecking=no" $node docker inspect drs)
#	  echo $docker_inspect_drs_strings > $DRS_LOGS_DEST/docker_inspect_drs_from_${host_name}.txt
#	  echo "Copy drs.ini from $host_name..."
#	   read -p "Press enter to continue: "
#    scp -o "StrictHostKeyChecking=no" $node:/etc/kolla/drs/drs.ini $DRS_LOGS_DEST/drs_ini_${host_name}.txt
#    echo "Save optimization list from $host_name..."
#    drs optimization list > $script_dir/drs_logs/optimization.list
#    echo "Save recommendation list from $host_name..."
#    drs recommendation list > $script_dir/drs_logs/recommendation.list
#    echo "Save migration list from $host_name..."
#    drs migration list > $script_dir/drs_logs/migration.list
#  done
#  add_to_archive $LOGS_TYPE $DRS_LOGS_DEST
#}

# args: service_name, src, dest, node_type
# exp: get_configs consul $CONSUL_CONF_SRC $CONSUL_LOGS_DEST ctrl
get_configs () {
  NODES_TYPE=$4
  echo -e "${yellow}Get $1 configs from $NODES_TYPE...${normal}"
  NODES=()
  get_nodes_list
  for node in "${NODES[@]}"; do
    host_name=$node
    echo "Copy $1 configs from $host_name..."
    mkdir -p $3/${host_name}_configs
    scp -rp -o "StrictHostKeyChecking=no" $node:$2/* $3/${host_name}_configs
  done
}

#get_consul_configs () {
#  NODES_TYPE="ctrl"
#  echo "Get consul configs from $NODES_TYPE..."
#  get_nodes_list
#  for node in "${NODES[@]}"; do
#    host_name=$node
#    echo "Copy consul configs from $host_name..."
#    mkdir -p $CONSUL_LOGS_DEST/${host_name}_configs
#    scp -rp -o "StrictHostKeyChecking=no" $node:$CONSUL_CONF_SRC/* $CONSUL_LOGS_DEST/${host_name}_configs
#  done
#}

#get_scheduler_cofigs () {
#  NODES_TYPE="ctrl"
#  echo "Get scheduler configs from $NODES_TYPE..."
#  get_nodes_list
#  for node in "${NODES[@]}"; do
#    host_name=$node
#    echo "Copy scheduler configs from $host_name..."
#    mkdir -p $NOVA_SCHEDULER_LOGS_DEST/${host_name}_configs
#    scp -rp -o "StrictHostKeyChecking=no" $node:$NOVA_SCHEDULER_CONF_SRC/* $NOVA_SCHEDULER_LOGS_DEST/${host_name}_configs
#  done
#}

#get_scheduler_logs

#get_consul_logs () {
#  NODES_TYPE="ctrl"
#  echo "Get consul logs from $NODES_TYPE..."
#  for node in "${NODES[@]}"; do
##	  host_name=$(cat /etc/hosts | grep -E ${node} | awk '{print $2}')
#    host_name=$node
#    echo "Copy consul logs from $host_name..."
#    scp -o "StrictHostKeyChecking=no" $node:$CONSUL_LOGS_SRC $CONSUL_LOGS_DEST/ha_log_from_$host_name.log
#    echo "Copy ha logs tail: ${TAIL_NUM} from $host_name..."
#	  tail_strings=$(ssh  -o "StrictHostKeyChecking=no" $node tail -$TAIL_NUM $CONSUL_LOGS_SRC)
#	  echo $tail_strings > $CONSUL_LOGS_DEST/ha_log_from_${host_name}_tail_${TAIL_NUM}.txt
#  done
#}

get_optimization_migration_drs () {
  echo "Save optimization list..."
  drs optimization list > $DRS_LOGS_DEST/optimization.list
  echo "Save recommendation list..."
  drs recommendation list > $DRS_LOGS_DEST/recommendation.list
  echo "Save migration list..."
  drs migration list > $DRS_LOGS_DEST/migration.list
}

get_drs_logs () {
#  mkdir -p $DRS_LOGS_DEST
  get_configs drs $DRS_CONF_SRC $DRS_LOGS_DEST ctrl
  get_logs drs $DRS_LOGS_SRC $DRS_LOGS_DEST ctrl $drs_container_name
  get_optimization_migration_drs
  add_to_archive drs $DRS_LOGS_DEST
}

get_ha_logs () {
#  mkdir -p $CONSUL_LOGS_DEST
  get_configs consul $CONSUL_CONF_SRC $CONSUL_LOGS_DEST ctrl
  get_logs consul $CONSUL_LOGS_SRC $CONSUL_LOGS_DEST ctrl $consul_container_name
  get_configs nova_scheduler $NOVA_SCHEDULER_CONF_SRC $NOVA_SCHEDULER_LOGS_DEST ctrl
  get_logs nova_scheduler $NOVA_SCHEDULER_LOGS_SRC $NOVA_SCHEDULER_LOGS_DEST ctrl $scheduler_container_name
  get_configs nova_compute $NOVA_COMPUTE_CONF_SRC $NOVA_COMPUTE_LOGS_DEST cmpt
  get_logs nova_compute $NOVA_COMPUTE_LOGS_SRC $NOVA_COMPUTE_LOGS_DEST cmpt $nova_compute_container_name
  cp -r $NOVA_SCHEDULER_LOGS_DEST $CONSUL_LOGS_DEST
  cp -r $NOVA_COMPUTE_LOGS_DEST $CONSUL_LOGS_DEST
  add_to_archive consul $CONSUL_LOGS_DEST
}

get_nova_logs () {
  mkdir -p $NOVA_LOGS_DEST
  get_configs nova_scheduler $NOVA_SCHEDULER_CONF_SRC $NOVA_SCHEDULER_LOGS_DEST ctrl
  get_logs nova_scheduler $NOVA_SCHEDULER_LOGS_SRC $NOVA_SCHEDULER_LOGS_DEST ctrl $scheduler_container_name
  get_configs nova_compute $NOVA_COMPUTE_CONF_SRC $NOVA_COMPUTE_LOGS_DEST cmpt
  get_logs nova_compute $NOVA_COMPUTE_LOGS_SRC $NOVA_COMPUTE_LOGS_DEST cmpt $nova_compute_container_name
  cp -r $NOVA_SCHEDULER_LOGS_DEST $NOVA_LOGS_DEST
  cp -r $NOVA_COMPUTE_LOGS_DEST $NOVA_LOGS_DEST
  add_to_archive nova $NOVA_LOGS_DEST
}


#check_host_command

case $LOGS_TYPE in
  drs)
    get_drs_logs
    ;;
  ha|consul)
    get_ha_logs
    ;;
  nova)
    get_nova_logs
    ;;
  *)
    echo "Type of logs: $LOGS_TYPE specify not correctly, try --help"
    exit 1
    ;;
esac
