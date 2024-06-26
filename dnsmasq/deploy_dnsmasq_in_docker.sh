#!/bin/bash

#The scrip deploy dnsmasq in docker
# docker installed needed
# /etc/hosts

#Error starting userland proxy: listen udp4 0.0.0.0:53: bind: address already in use
#sudo systemctl stop systemd-resolved
#sudo systemctl disable systemd-resolved

#nc -vzu <IP> 53

script_dir=$(dirname $0)

[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $DNS_SERVER_IP ]] && DNS_SERVER_IP=""
[[ -z $CONF_NAME ]] && CONF_NAME="dnsmasq.conf"

get_var () {
  echo "Get vars..."
  # get DOAMIN
  if [[ -z "${DOAMIN}" ]]; then
    read -rp "Enter domain name [test.domain]: " DOMAIN
  fi
  export DOMAIN=${DOMAIN:-"test.domain"}

  # get DNS_SERVER_IP
  while [ -z "${DNS_SERVER_IP}" ]; do
    if [[ -z "${DNS_SERVER_IP}" ]]; then
      read -rp "Enter DNS SERVER IP: " $DNS_SERVER_IP
    fi
    export DNS_SERVER_IP=${DNS_SERVER_IP}
  done

  echo $DOMAIN
  echo $DNS_SERVER_IP
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
  echo
}

deploy_dnsmasq_cont () {
  docker compose -f $script_dir/docker-compose.yml up -d
}


get_var
sed_var_in_conf
cat_conf
read -p "Press enter to continue: "
deploy_dnsmasq_cont

