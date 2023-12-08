#!/bin/bash

#scp drs logs from controls
#On home pc: scp root@<lcm_ip>:~/test_scripts_keystack/drs_logs/* C:\Users\bochk\drs_logs

TAIL_NUM=100
nodes_to_find="\-ctrl\-..$"
drs_logs_folder=./drs_logs

mkdir ./drs_logs
srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}')
for host in $srv; do
	host_name=$(cat /etc/hosts | grep -E ${host} | awk '{print $2}')
        echo "Copy drs logs from $host_name..."
        scp -o "StrictHostKeyChecking=no" $host:/var/log/kolla/drs/drs.log ./drs_logs/drs_log_from_$host_name
        echo "Copy drs logs tail: ${TAIL_NUM} from $host_name..."
	tail_strins=$(ssh  -o "StrictHostKeyChecking=no" $host tail -$TAIL_NUM /var/log/kolla/drs/drs.log)
	echo $tail_strins > ./drs_logs/drs_log_from_${host_name}_tail_${TAIL_NUM}.txt
	echo "Copy drs.ini from $host_name..."
        scp -o "StrictHostKeyChecking=no" $host:/etc/kolla/drs/drs.ini ./drs_logs/drs_ini_${host_name}.txt
done
