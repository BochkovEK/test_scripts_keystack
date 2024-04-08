#!/bin/bash

# Script for get DRS logs

#On home pc:
# scp root@<lcm_ip>:~/test_scripts_keystack/drs-*.gz .

# unpacking: tar -xvzf drs-logs-08-04-2024.tar.gz -C ./

#cleanup on drs_logs folder: rm -f drs*.txt drs*.log migration.list optimization.list recommendation.list


comp_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"

script_dir=$(dirname $0)

[[ -z $TAIL_NUM ]] && TAIL_NUM=100
[[ -z $NODES_TO_FIND ]] && NODES_TO_FIND=$ctrl_pattern
[[ -z $DRS_LOGS_SRC ]] && DRS_LOGS_SRC=/var/log/kolla/drs/drs.log
[[ -z $DRS_LOGS_DEST ]] && DRS_LOGS_DEST=$script_dir/drs_logs
[[ -z $AUTOEVA_LOGS_SRC ]] && AUTOEVA_LOGS_SRC=/var/log/kolla/autoevacuate.log
[[ -z $AUTOEVA_LOGS_DEST ]] && AUTOEVA_LOGS_DEST=$script_dir/autoeva_logs
[[ -z $LOGS_TYPE ]] && LOGS_TYPE='drs'

#======================

note_type_func () {
  case "$1" in
        ctrl)
          NODES_TO_FIND=$ctrl_pattern
          echo "Сontainer will be checked on ctrl nodes"
          ;;
        comp)
          NODES_TO_FIND=$comp_pattern
          echo "Сontainer will be checked on comp nodes"
          ;;
        net)
          NODES_TO_FIND=$net_pattern
          echo "Сontainer will be checked on net nodes"
          ;;
        *)
          echo "type is not specified correctly. Сontainers will be checked on ctr, comp, net nodes"
          ;;
        esac
}
#==============================

while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      -nt,    -type_of_nodes     <type_of_nodes> 'ctrl', 'comp', 'net'
      -l,     -logs               <logs_type> 'drs', 'ha'
      "
      exit 0
      break ;;
	-nt|-type_of_nodes)
      echo "Found the -type_of_nodes  with parameter value $2"
      note_type_func "$2"
      shift ;;
  -l|-logs) LOGS_TYPE="$2"
	  echo "Found the -logs <logs_type>, with parameter value $LOGS_TYPE"
    shift ;;
  --) shift
    break ;;
  *) echo "$1 is not an option";;
    esac
    shift
done

get_drs_logs () {
  mkdir -p $DRS_LOGS_DEST
  ABSOLUTE_DRS_LOGS_DEST=$(realpath $DRS_LOGS_DEST)
  echo "distinction drs logs: $DRS_LOGS_DEST"
  srv=$(cat /etc/hosts | grep -E ${NODES_TO_FIND} | awk '{print $2}')
  for host in $srv; do
	  host_name=$(cat /etc/hosts | grep -E ${host} | awk '{print $2}')
    echo "Copy drs logs from $host_name..."
    scp -o "StrictHostKeyChecking=no" $host:$DRS_LOGS_SRC $DRS_LOGS_DEST/drs_log_from_$host_name.log
    echo "Copy drs logs tail: ${TAIL_NUM} from $host_name..."
	  tail_strins=$(ssh  -o "StrictHostKeyChecking=no" $host tail -$TAIL_NUM $DRS_LOGS_SRC)
	  echo $tail_strins > $DRS_LOGS_DEST/drs_log_from_${host_name}_tail_${TAIL_NUM}.txt
	  echo "Copy drs.ini from $host_name..."
    scp -o "StrictHostKeyChecking=no" $host:/etc/kolla/drs/drs.ini $DRS_LOGS_DEST/drs_ini_${host_name}.txt
    echo "Save optimization list from $host_name..."
    drs optimization list > $script_dir/drs_logs/optimization.list
    echo "Save recommendation list from $host_name..."
    drs recommendation list > $script_dir/drs_logs/recommendation.list
    echo "Save migration list from $host_name..."
    drs migration list > $script_dir/drs_logs/migration.list
  done
  echo "Add logs to archive... drs-logs-"`date +"%d-%m-%Y"`""
  [ -e $script_dir/$archive_logs_name.tar.gz ] && rm $script_dir/$archive_logs_name.tar.gz
  archive_logs_name=$(echo drs-logs-"`date +"%d-%m-%Y"`")
  echo "tar -czvf $script_dir/$archive_logs_name.tar.gz $DRS_LOGS_DEST"
  tar -czvf $script_dir/$archive_logs_name.tar.gz $DRS_LOGS_DEST
}

get_ha_logs () {
  mkdir $AUTOEVA_LOGS_DEST
  srv=$(cat /etc/hosts | grep -E ${NODES_TO_FIND} | awk '{print $2}')
  for host in $srv; do
	  host_name=$(cat /etc/hosts | grep -E ${host} | awk '{print $2}')
    echo "Copy ha logs from $host_name..."
    scp -o "StrictHostKeyChecking=no" $host:$AUTOEVA_LOGS_SRC $AUTOEVA_LOGS_DEST/ha_log_from_$host_name.log
    echo "Copy ha logs tail: ${TAIL_NUM} from $host_name..."
	  tail_strins=$(ssh  -o "StrictHostKeyChecking=no" $host tail -$TAIL_NUM $AUTOEVA_LOGS_SRC)
	  echo $tail_strins > $AUTOEVA_LOGS_DEST/ha_log_from_${host_name}_tail_${TAIL_NUM}.txt
  done
}

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
