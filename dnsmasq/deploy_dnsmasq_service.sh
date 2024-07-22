#!/bin/bash

# The script install dnsmasq
# for mapping "ip - name" add string to dns_ip_mapping.txt file like /etc/hosts

#Error starting userland proxy: listen udp4 0.0.0.0:53: bind: address already in use
#sudo systemctl stop systemd-resolved
#sudo systemctl disable systemd-resolved

#nc -vzu <IP> 53

script_dir=$(dirname $0)
nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)|\-net\-..( |$)|\-lcm\-..( |$)'
yellow=`tput setaf 3`
reset=`tput sgr0`

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

  echo -e "\n${yellow}Output ip a:${reset}"
  echo "-----------------------"
  ip a
  echo -e "-----------------------\n"

  # get DNS_SERVER_IP
  while [ -z "${DNS_SERVER_IP}" ]; do
    if [[ -z "${DNS_SERVER_IP}" ]]; then
      read -rp "Enter DNS SERVER IP: " DNS_SERVER_IP
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
  sed -i --regexp-extended "s/DNS_SERVER_IP/$DNS_SERVER_IP/" \
      $script_dir/$CONF_NAME
}

cat_conf () {
  echo "Cat conf..."
  cat $script_dir/$CONF_NAME
  echo
}

install_dnsmasq () {
  #Install docker if need
  if ! command -v dnsmasq &> /dev/null; then
    is_ubuntu=$(cat /etc/os-release|grep ubuntu)
    if [ -n "$is_ubuntu" ]; then
      echo "Installing dnsmasq on ubuntu"
      sudo apt install -y dnsmasq
    fi
    is_sberlinux=$(cat /etc/os-release|grep sberlinux)
    if [ -n "$is_sberlinux" ]; then
      echo "Installing dnsmasq on sberlinux"
      sudo yum in -y dnsmasq
    fi
    systemctl enable dnsmasq --now
  fi
}

copy_dnsmasq_conf () {
  cp $script_dir/$CONF_NAME /etc/$CONF_NAME
  cat $script_dir/dns_ip_mapping.txt >> /etc/hosts
  sed -i --regexp-extended "s/nameserver(\s+|)[0-9]+.[0-9]+.[0-9]+.[0-9]+/nameserver $DNS_SERVER_IP/" \
      /etc/resolv.conf
#  echo "nameserver $DNS_SERVER_IP" >> /etc/resolv.conf
  systemctl restart dnsmasq
  srv=$(cat /etc/hosts | grep -E "$nodes_to_find" | awk '{print $1}')
  for host in $srv;do
    echo "Remove resolv.conf from $(cat /etc/hosts | grep -E ${host} | awk '{print $2}'):"
    ssh -o StrictHostKeyChecking=no -t $host "rm /etc/resolv.conf"
    echo "Copy resolv.conf to $(cat /etc/hosts | grep -E ${host} | awk '{print $2}'):"
    scp /etc/resolv.conf $host:/etc/resolv.conf
  done
}

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The script install dnsmasq
        To deploy dnsmasq on DNS server:
        1) Edit dns_ip_mapping.txt file like /etc/hosts to mapping <ip> <nameserver>
        2) bash $HOME/test_script_keystack/dnsmasq/deploy_dnsmasq_service.sh
        "
          exit 0
          break ;;
	      --) shift
          break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

get_var
sed_var_in_conf
cat_conf
read -p "Press enter to continue: "
install_dnsmasq
copy_dnsmasq_conf

