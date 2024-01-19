#!/bin/bash

CTRL_NODES='\-ctrl\-..( |$)'
TAIL_NUM=100

CYAN='\033[0;36m'
BLUE='\033[0;34m'
ORANGE='\033[43m'
NC='\033[0m' # No Color

srv=$(cat /etc/hosts | grep -E "$CTRL_NODES" | awk '{print $1}')
for host in $srv;do
    echo -e "${CYAN}Drs logs on $(cat /etc/hosts | grep -E ${host} | awk '{print $2}'):${NC}"
    ssh -o StrictHostKeyChecking=no $host tail -${TAIL_NUM} /var/log/kolla/drs/drs.log; echo -e "${BLUE}`date`${NC}"
    echo -e "${ORANGE}For read all log on $host: ssh -o StrictHostKeyChecking=no $host less /var/log/kolla/drs/drs.log${NC}"
done
