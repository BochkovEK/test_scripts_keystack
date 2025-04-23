#!/bin/bash

#Colors
normal=$(tput sgr0)
yellow=$(tput setaf 3)
interface_name="eth0"

echo "Start flapping interface test script..."
echo -e "${yellow}[WARNING]: This script must be executed on the node where the interface is being disabled(flapping).${normal}"
if [ -z "$1" ]; then
    if [ -z "$INTERFACE_NAME" ]; then
      echo "Interface name can be defined either as argument or environment variable 'INTERFACE_NAME'"
      INTERFACE_NAME=$interface_name
      echo "Interface name is set by default: '$INTERFACE_NAME'"
    else
      echo "Interface name is: '$INTERFACE_NAME'"
    fi
else
  INTERFACE_NAME=$1
  echo "Interface name is: '$INTERFACE_NAME'"
fi

read -p "Press enter to continue: "

for (( c=1; c<=20; c++ )); do
	echo "Interface $INTERFACE_NAME down"
	ip link set $INTERFACE_NAME down
	sleep 5s
	echo "Interface $INTERFACE_NAME up"
	ip link set $INTERFACE_NAME up
	sleep 5s
	date
done
echo "Finish"
