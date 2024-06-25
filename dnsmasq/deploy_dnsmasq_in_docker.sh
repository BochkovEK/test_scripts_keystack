#!/bin/bash

#The scrip deploy dnsmasq in docker
# docker installed needed

[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $IP_LCM ]] && IP_LCM=""

# get DOAMIN
if [[ -z "${DOAMIN}" ]]; then
  read -rp "Enter domain name [test.domain]: " DOMAIN
fi
export DOMAIN=${DOMAIN:-"test.domain"}

# get IP_LCM
while [ -z "${IP_LCM}" ]; do
  if [[ -z "${IP_LCM}" ]]; then
    read -rp "Enter LCM IP: " IP_LCM
  fi
  export IP_LCM=${IP_LCM}
done

echo $DOMAIN
echo $IP_LCM

