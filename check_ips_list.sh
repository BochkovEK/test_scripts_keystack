#!/bin/bash

BASE_IP=10.224.140
START=97
END=126

## save $START, just in case if we need it later ##
i=$START
while [[ $i -le $END ]]; do
	echo "$BASE_IP.$i"
	ping -c 2 $BASE_IP.$i &> /dev/null
	if ping -c 2 $IP &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $BASE_IP.$i - success${normal}"
#    [ "$ONLY_PING" == "false" ] && { ssh -t -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$IP "$COMMAND_STR"; }
  else
    printf "%40s\n" "${red}No connection with $IP - error!${normal}"
  fi
  ((i = i + 1))
done