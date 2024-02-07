#!/bin/bash

#scp drs logs from controls
#On home pc: scp root@<lcm_ip>:~/test_scripts_keystack/drs_logs/* C:\Users\bochk\drs_logs


comp_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"

[[ -z $TAIL_NUM ]] && TAIL_NUM=100
[[ -z $DRS_LOGS_SRC ]] && DRS_LOGS_SRC=/var/log/kolla/drs/drs.log
[[ -z $DRS_LOGS_DEST ]] && DRS_LOGS_DEST=./drs_logs
[[ -z $AUTOEVA_LOGS_SRC ]] && AUTOEVA_LOGS_SRC=/var/log/kolla/autoevacuate.log
[[ -z $AUTOEVA_LOGS_DEST ]] && AUTOEVA_LOGS_DEST=./autoeva_logs
[[ -z $LOGS_TYPE ]] && LOGS_TYPE='drs'

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
  mkdir $DRS_LOGS_DEST
  srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}')
  for host in $srv; do
	  host_name=$(cat /etc/hosts | grep -E ${host} | awk '{print $2}')
    echo "Copy drs logs from $host_name..."
    scp -o "StrictHostKeyChecking=no" $host:$DRS_LOGS_SRC $DRS_LOGS_DEST/drs_log_from_$host_name
    echo "Copy drs logs tail: ${TAIL_NUM} from $host_name..."
	  tail_strins=$(ssh  -o "StrictHostKeyChecking=no" $host tail -$TAIL_NUM $DRS_LOGS_SRC)
	  echo $tail_strins > $DRS_LOGS_DEST/drs_log_from_${host_name}_tail_${TAIL_NUM}.txt
	  echo "Copy drs.ini from $host_name..."
    scp -o "StrictHostKeyChecking=no" $host:/etc/kolla/drs/drs.ini $DRS_LOGS_DEST/drs_ini_${host_name}.txt
  done
}

get_ha_logs () {
  mkdir $AUTOEVA_LOGS_DEST
  srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}')
  for host in $srv; do
	  host_name=$(cat /etc/hosts | grep -E ${host} | awk '{print $2}')
    echo "Copy ha logs from $host_name..."
    scp -o "StrictHostKeyChecking=no" $host:$AUTOEVA_LOGS_SRC $DRS_LOGS_DEST/ha_log_from_$host_name
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
