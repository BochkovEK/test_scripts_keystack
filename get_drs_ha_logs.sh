#!/bin/bash

# Script for get DRS logs

#On home pc:
# scp root@<lcm_ip>:~/test_scripts_keystack/drs-*.gz .

# unpacking: tar -xvzf drs-logs-08-04-2024.tar.gz -C ./

#cleanup on drs_logs folder: rm -f drs*.txt drs*.log migration.list optimization.list recommendation.list

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

#comp_pattern="\-comp\-..$"
#ctrl_pattern="\-ctrl\-..$"
#net_pattern="\-net\-..$"

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
get_nodes_list_script="get_nodes_list.sh"
install_package_script="install_package.sh"

[[ -z $TAIL_NUM ]] && TAIL_NUM=100
[[ -z $NODES_TYPE ]] && NODES_TYPE="ctrl"
#[[ -z $NODES_TO_FIND ]] && NODES_TO_FIND="ctrl"
[[ -z $DRS_LOGS_SRC ]] && DRS_LOGS_SRC=/var/log/kolla/drs/drs.log
[[ -z $DRS_LOGS_DEST ]] && DRS_LOGS_DEST=$script_dir/drs_logs
[[ -z $AUTOEVA_LOGS_SRC ]] && AUTOEVA_LOGS_SRC=/var/log/kolla/autoevacuate.log
[[ -z $AUTOEVA_LOGS_DEST ]] && AUTOEVA_LOGS_DEST=$script_dir/consul_logs
[[ -z $LOGS_TYPE ]] && LOGS_TYPE='drs'

#======================

#note_type_func () {
#  case "$1" in
#        ctrl)
#          NODES_TO_FIND=$ctrl_pattern
#          echo "Сontainer will be checked on ctrl nodes"
#          ;;
#        comp)
#          NODES_TO_FIND=$comp_pattern
#          echo "Сontainer will be checked on comp nodes"
#          ;;
#        net)
#          NODES_TO_FIND=$net_pattern
#          echo "Сontainer will be checked on net nodes"
#          ;;
#        *)
#          echo "type is not specified correctly. Сontainers will be checked on ctr, comp, net nodes"
#          ;;
#        esac
#}
#==============================

while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      -l,     -logs              <logs_type> 'drs', 'ha'
      "
      exit 0
      break ;;
  -l|-logs) LOGS_TYPE="$2"
	  echo "Found the -logs <logs_type>, with parameter value $LOGS_TYPE"
    shift ;;
  --) shift
    break ;;
  *) echo "$1 is not an option";;
    esac
    shift
done

# Check_host_command
#check_host_command () {
#  Check_command host
#  if [ -z $command_exist ]; then
#    echo -e "\033[33mbind-utils not installed\033[0m"
#    read -p "Press enter to install bind-utils: "
#    is_sber_os=$(cat /etc/os-release| grep 'NAME="SberLinux"')
#    if [ -n "${is_sber_os}" ]; then
#      yum in -y bind-utils
#    fi
#  else
#    printf "%s\n" "${green}'host' command is available - success${normal}"
#  fi
#}

check_host_command () {
  if ! bash $utils_dir/$install_package_script host; then
    echo -e "${red}Failed to check 'host' command - ERROR${normal}"
    exit 1
  fi
#  Check_command host
#  if [ -z $command_exist ]; then
#    echo -e "\033[33mbind-utils not installed\033[0m"
#    read -p "Press enter to install bind-utils: "
#    is_sber_os=$(cat /etc/os-release| grep 'NAME="SberLinux"')
#    if [ -n "${is_sber_os}" ]; then
#      yum in -y bind-utils
#    fi
#  else
#    printf "%s\n" "${green}'host' command is available - success${normal}"
#  fi
}

add_to_archive () {
  echo "Add logs to archive... $1-logs-"`date +"%d-%m-%Y"`""
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

get_drs_logs () {
  mkdir -p $DRS_LOGS_DEST
  ABSOLUTE_DRS_LOGS_DEST=$(realpath $DRS_LOGS_DEST)
  echo "distinction drs logs: $DRS_LOGS_DEST"
#  srv=$(cat /etc/hosts | grep -E ${NODES_TO_FIND} | awk '{print $2}')
#  [[ -z "${srv}" ]] && {
#    printf "%s\n" "${red}It was not possible to separate the names and addresses of control nodes from the hosts file - error!${normal}";
#    #echo "It was not possible to separate the names and addresses of control nodes from the hosts file";
#    exit 1;
#    }
  for node in "${NODES[@]}"; do
#	  host_name=$(cat /etc/hosts | grep -E ${node} | awk '{print $2}')
#    [[ -z $host_name ]] && { host_name=$node; }
    host_name=$node
#    echo $node
    echo "Copy drs logs from $host_name..."
    echo "DRS_LOGS_SRC: $DRS_LOGS_SRC"
    read -p "Press enter to continue: "
    scp -o "StrictHostKeyChecking=no" $node:$DRS_LOGS_SRC $DRS_LOGS_DEST/drs_log_from_$host_name.log
    echo "Copy drs logs tail: ${TAIL_NUM} from $host_name..."
     read -p "Press enter to continue: "
	  tail_strings=$(ssh -o "StrictHostKeyChecking=no" $node tail -n $TAIL_NUM $DRS_LOGS_SRC)
	  echo $tail_strings > $DRS_LOGS_DEST/drs_log_from_${host_name}_tail_${TAIL_NUM}.txt
	  echo "Copy docker logs drs from $host_name..."
	   read -p "Press enter to continue: "
	  docker_logs_drs_strings=$(ssh -t -o "StrictHostKeyChecking=no" $node docker logs drs) #&> /dev/null)
	  echo $docker_logs_drs_strings > $DRS_LOGS_DEST/docker_logs_drs_from_${host_name}.txt
	  echo "Copy docker inspect drs from $host_name..."
	   read -p "Press enter to continue: "
	  docker_inspect_drs_strings=$(ssh -o "StrictHostKeyChecking=no" $node docker inspect drs)
	  echo $docker_inspect_drs_strings > $DRS_LOGS_DEST/docker_inspect_drs_from_${host_name}.txt
	  echo "Copy drs.ini from $host_name..."
	   read -p "Press enter to continue: "
    scp -o "StrictHostKeyChecking=no" $node:/etc/kolla/drs/drs.ini $DRS_LOGS_DEST/drs_ini_${host_name}.txt
    echo "Save optimization list from $host_name..."
    drs optimization list > $script_dir/drs_logs/optimization.list
    echo "Save recommendation list from $host_name..."
    drs recommendation list > $script_dir/drs_logs/recommendation.list
    echo "Save migration list from $host_name..."
    drs migration list > $script_dir/drs_logs/migration.list
  done
  add_to_archive $LOGS_TYPE $DRS_LOGS_DEST
#  echo "Add logs to archive... $LOGS_TYPE-logs-"`date +"%d-%m-%Y"`""
#  [ -e $script_dir/$archive_logs_name.tar.gz ] && rm $script_dir/$archive_logs_name.tar.gz
#  archive_logs_name=$(echo $LOGS_TYPE-logs-"`date +"%d-%m-%Y"`")
#  echo "tar -czvf $script_dir/$archive_logs_name.tar.gz $DRS_LOGS_DEST"
#  tar -czvf $script_dir/$archive_logs_name.tar.gz $DRS_LOGS_DEST
}

get_ha_logs () {
  mkdir $AUTOEVA_LOGS_DEST
#  srv=$(cat /etc/hosts | grep -E ${NODES_TO_FIND} | awk '{print $2}')
  for node in "${NODES[@]}"; do
#	  host_name=$(cat /etc/hosts | grep -E ${node} | awk '{print $2}')
    host_name=$node
    echo "Copy ha logs from $host_name..."
    scp -o "StrictHostKeyChecking=no" $node:$AUTOEVA_LOGS_SRC $AUTOEVA_LOGS_DEST/ha_log_from_$host_name.log
    echo "Copy ha logs tail: ${TAIL_NUM} from $host_name..."
	  tail_strings=$(ssh  -o "StrictHostKeyChecking=no" $node tail -$TAIL_NUM $AUTOEVA_LOGS_SRC)
	  echo $tail_strings > $AUTOEVA_LOGS_DEST/ha_log_from_${host_name}_tail_${TAIL_NUM}.txt
  done
  add_to_archive $LOGS_TYPE $AUTOEVA_LOGS_DEST
}

check_host_command
get_nodes_list

case $LOGS_TYPE in

  drs)
    get_drs_logs
    ;;

  ha)
    get_ha_logs
    ;;

  *)
    echo "Type of logs: $LOGS_TYPE specify not correctly"
    exit 1
    ;;
esac
