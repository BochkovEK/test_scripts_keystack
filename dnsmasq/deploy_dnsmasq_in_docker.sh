#!/bin/bash

#The scrip deploy dnsmasq in docker
# docker installed needed
# /etc/hosts

script_dir=$(dirname $0)

[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $IP_LCM ]] && IP_LCM=""
[[ -z $CONF_NAME ]] && CONF_NAME="dnsmasq.conf"

get_var () {
  echo "Get vars..."
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
}

sed_var_in_conf () {
  echo "Sed vars in conf..."
  sed -i --regexp-extended "s/DOMAIN/$DOMAIN/" \
      $script_dir/$CONF_NAME
  sed -i --regexp-extended "s/IP_LCM/$IP_LCM/" \
      $script_dir/$CONF_NAME
}

cat_conf () {
  echo "Cat conf..."
  cat $script_dir/$CONF_NAME
}

deploy_dnsmasq_cont () {
  docker compose -f $script_dir/docker-compose.yaml up -d
}


get_var
sed_var_in_conf
cat_conf
read -p "\nPress enter to continue: "
deploy_dnsmasq_cont

