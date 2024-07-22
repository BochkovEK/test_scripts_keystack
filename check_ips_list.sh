#!/bin/bash


#Colors
#Color       #define       Value       RGB
#black     COLOR_BLACK       0     0, 0, 0
#red       COLOR_RED         1     max,0,0
#green     COLOR_GREEN       2     0,max,0
#yellow    COLOR_YELLOW      3     max,max,0
#blue      COLOR_BLUE        4     0,0,max
#magenta   COLOR_MAGENTA     5     max,0,max
#cyan      COLOR_CYAN        6     0,max,max
#white     COLOR_WHITE       7     max,max,max
normal=$(tput sgr0)
yellow=$(tput setaf 3)

BASE_IP=10.224.140
START=97
END=126

## save $START, just in case if we need it later ##
i=$START
while [[ $i -le $END ]]; do
	echo "$BASE_IP.$i"
	ping -c 2 $BASE_IP.$i &> /dev/null
	if ping -c 2 $IP &> /dev/null; then
    printf "%40s\n" "${yellow}There is a connection with $BASE_IP.$i - success${normal}"
#    [ "$ONLY_PING" == "false" ] && { ssh -t -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$IP "$COMMAND_STR"; }
  else
    printf "%40s\n" "No connection with $IP - error!"
  fi
  ((i = i + 1))
done