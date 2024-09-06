#!/bin/bash

# The script install dnsmasq
# for mapping "ip - name" add string to dns_ip_mapping.txt file like /etc/hosts

#Error starting userland proxy: listen udp4 0.0.0.0:53: bind: address already in use
#sudo systemctl stop systemd-resolved
#sudo systemctl disable systemd-resolved

#nc -vzu <IP> 53

script_dir=$(dirname $0)
nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)|\-net\-..( |$)|\-lcm\-..( |$)'
dns_ip_mapping=dns_ip_mapping.txt
#parses_file=$script_dir/dns_ip_mapping.txt
parses_file=/etc/hosts
yellow=`tput setaf 3`
reset=`tput sgr0`

[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $DNS_SERVER_IP ]] && DNS_SERVER_IP=""
[[ -z $CONF_NAME ]] && CONF_NAME="dnsmasq.conf"

#The script parses dns_ip_mapping.txt to find IPs for \$nodes_to_find and
 #          add DNS IP to /etc/resolv.conf all of them

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The script install dnsmasq
        To deploy dnsmasq on DNS server:
        1) Edit $dns_ip_mapping file like /etc/hosts to mapping <ip> <nameserver>

cat <<-EOF > ~/test_scripts_keystack/dnsmasq/dns_ip_mapping.txt
# ----- ADD from deploy_dnsmasq_service.sh -----
10.224.129.227 int.ebochkov.test.domain
10.224.129.228 ext.ebochkov.test.domain

10.224.129.236 ebochkov-keystack-comp-01 comp-01

10.224.129.230 ebochkov-keystack-ctrl-01 ctrl-01

10.224.129.235 ebochkov-keystack-lcm-01 lcm-01 lcm-nexus.test.domain netbox.test.domain gitlab.test.domain vault.test.domain
10.224.129.246 ebochkov-keystack-net-01 net-01
10.224.130.27 ebochkov-keystack-add_vm-01 nexus.test.domain
EOF

        2) permissionless access to all stand nodes is required
          The script parses the $dns_ip_mapping file for the presence of the following pattern:
           $nodes_to_find
           and edits /etc/resolv.conf on all of them
        3) bash $script_dir/deploy_dnsmasq_service.sh

        Note:
        Every time /etc/dnsmasq.conf and /etc/hosts are changed, restart the service 'systemctl restart dnsmasq'
        "
          exit 0
          break ;;
	      --) shift
          break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

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

  echo -e "\n${yellow}vars:${reset}"
  echo DOMAIN: $DOMAIN
  echo DNS_SERVER_IP: $DNS_SERVER_IP
  echo
}

sed_var_in_conf () {
  echo -e "\n${yellow}Sed vars in conf...${reset}"
  sed -i --regexp-extended "s/DOMAIN/$DOMAIN/" \
      $script_dir/$CONF_NAME
  sed -i --regexp-extended "s/DNS_SERVER_IP/$DNS_SERVER_IP/" \
      $script_dir/$CONF_NAME
  echo
}

#cat_conf () {
#  echo "Cat conf..."
#  echo
#  cat $script_dir/$CONF_NAME
#  echo ""
#}

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
  srv=$(cat $parses_file | grep -E "$nodes_to_find" | awk '{print $1}')
  for host in $srv;do
    echo "Remove resolv.conf from $(cat $parses_file | grep -E ${host} | awk '{print $2}'):"
    ssh -o StrictHostKeyChecking=no -t $host "rm /etc/resolv.conf"
    echo "Copy resolv.conf to $(cat $parses_file | grep -E ${host} | awk '{print $2}'):"
    scp /etc/resolv.conf $host:/etc/resolv.conf
  done
}


get_var
sed_var_in_conf
echo -e "\n${yellow}Cat conf...${reset}"
echo
cat $script_dir/$CONF_NAME
echo
echo -e "\n${yellow}Cat $dns_ip_mapping...${reset}"
echo
cat $script_dir/$dns_ip_mapping
echo
read -p "Press enter to continue: "
install_dnsmasq
copy_dnsmasq_conf

