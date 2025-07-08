#!/bin/bash

# check for elevated privileges
if ((${EUID:-0} || "$(id -u)")); then
  echo This script has to be run as root or sudo.
  exit 1
fi

if [[ -z "${ERASE}" ]]; then
  unset ERASE
  read -rp "Are you sure you want to erase all data? y/n [n]: " ERASE
else
  ERASE=$ERASE
fi

if [[ $ERASE == "y" ]]; then
  echo
  echo -e "\e[31WARNING. It is DESTROY ALL DATA!\e[0m"
  read -n1 -srp "Press any key to continue or CTRL+C to break "
  echo
  echo "DESTROY ALL DATA......."
  echo
else
  exit 13;
fi

. ./settings

cd ~ || exit

docker compose -f $CFG_HOME/netbox-compose.yml down
docker compose -f $CFG_HOME/compose.yaml down
docker system prune -f
docker volume prune -f

rm -rf $INSTALL_HOME
