#!/bin/bash

# The script install dnsmasq
# for mapping "ip - name" add string to dns_ip_mapping.txt file like /etc/hosts

#Error starting userland proxy: listen udp4 0.0.0.0:53: bind: address already in use
#sudo systemctl stop systemd-resolved
#sudo systemctl disable systemd-resolved

#Every time /etc/dnsmasq.conf and /etc/hosts are changed, restart the service 'systemctl restart dnsmasq'

#nc -vzu <IP> 53

script_dir=$(dirname $0)
script_name=$(basename "$0")
nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)|\-net\-..( |$)|\-lcm\-..( |$)'
add_string="# ------ ADD strings ------"
ldap_string="LDAP SERVER"
ldap_server="10.224.133.139 ldaps-lab.slavchenkov-keystack.vm.lab.itkey.com"
dns_ip_mapping_file_name=dns_ip_mapping.txt
#parses_file=$script_dir/dns_ip_mapping.txt
parses_file=/etc/hosts


#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $DNS_SERVER_IP ]] && DNS_SERVER_IP=""
[[ -z $CONF_NAME ]] && CONF_NAME="dnsmasq.conf"
[[ -z $HOST_EXIST ]] && HOST_EXIST="false"
[[ -z $DNS_IP_MAPPING_FILE ]] && DNS_IP_MAPPING_FILE=$script_dir/$dns_ip_mapping_file_name

#The script parses dns_ip_mapping.txt to find IPs for \$nodes_to_find and
 #          add DNS IP to /etc/resolv.conf all of them

while [ -n "$1" ]
do
    case "$1" in
        -host_exist) HOST_EXIST="true"
          ;;
        -dns_ip_mapping_file) DNS_IP_MAPPING_FILE=$2
          echo "Found the -dns_ip_mapping_file option, with parameter value $DNS_IP_MAPPING_FILE"
          shift
          ;;
        --help) echo -E "
        The script install dnsmasq
        To deploy dnsmasq on DNS server:
        1) Edit $dns_ip_mapping_file_name file like /etc/hosts to mapping <ip> <nameserver>

cat <<-EOF > ~/test_scripts_keystack/dnsmasq/dns_ip_mapping.txt
10.224.129.227 int.ebochkov.test.domain
10.224.129.228 ext.ebochkov.test.domain

10.224.129.236 ebochkov-keystack-comp-01 comp-01

10.224.129.230 ebochkov-keystack-ctrl-01 ctrl-01

10.224.129.235 ebochkov-keystack-lcm-01 lcm-01 lcm-nexus.test.domain netbox.test.domain gitlab.test.domain vault.test.domain
10.224.129.246 ebochkov-keystack-net-01 net-01
10.224.130.27 ebochkov-keystack-add_vm-01 nexus.test.domain
EOF

        2) permissionless access to all stand nodes is required
          The script parses the $dns_ip_mapping_file file for the presence of the following pattern:
           $nodes_to_find
           and edits /etc/resolv.conf on all of them
        3)
          a) bash $script_dir/$script_name
          b) bash $script_dir/$script_name -host_exist (if file 'hosts' already edited)

        Note:
        Every time /etc/dnsmasq.conf and /etc/hosts are changed, restart the service 'systemctl restart dnsmasq'

        -host_exist                                       if 'hosts' file already edited (without parameter)
        -dns_ip_mapping_file  <dns_ip_mapping_file_path>  path to dns ip mapping file like 'hosts'
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



  # get DNS_SERVER_IP
  dns_mgmt_ip=$(ip a|grep mgmt|grep inet|grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,3}' \
  |awk '{p=index($1,"/");print substr($1,0,p-1)}')

  export DNS_SERVER_IP=$dns_mgmt_ip
  echo -e "DNS_SERVER_IP: $DNS_SERVER_IP\n"
  while [ -z "${DNS_SERVER_IP}" ]; do
    if [[ -z "${DNS_SERVER_IP}" ]]; then
      echo -e "\n${yellow}Output ip a:${normal}"
      echo "-----------------------"
      ip a
      echo -e "-----------------------\n"
      read -rp "Enter DNS SERVER IP: " DNS_SERVER_IP
    fi
    DNS_SERVER_IP=$(echo "${DNS_SERVER_IP%/*}")
    export DNS_SERVER_IP=${DNS_SERVER_IP}
  done

  echo -e "\n${yellow}vars:${normal}"
  echo DOMAIN: $DOMAIN
  echo DNS_SERVER_IP: $DNS_SERVER_IP
  echo
}

sed_var_in_conf () {
  echo -e "\n${yellow}Sed vars in conf...${normal}"
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
# ???
#      systemd_resolved_enabled=$(systemctl list-unit-files | grep enabled| grep systemd-resolved)
#      if [ -n "$systemd_resolved_enabled" ]; then
#        systemctl stop systemd-resolved
#        systemctl disable systemd-resolved
#      fi
      apt update
      apt install -y dnsmasq
      systemctl stop systemd-resolved
      systemctl disable systemd-resolved
      systemctl restart dnsmasq
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
  cp "$script_dir"/$CONF_NAME /etc/$CONF_NAME
  # Checking the hosts file for the line # ----- ADD from deploy_dnsmasq_service.sh -----
  if [ "$HOST_EXIST" = false ]; then
    strings_from_dnsmasq_deployer=$(cat < $parses_file|grep "$add_string")
    if [ -z "$strings_from_dnsmasq_deployer" ]; then
      cp $parses_file "$script_dir"/hosts_backup
    else
      cp "$script_dir"/hosts_backup $parses_file
    fi
    echo "$add_string" >> $parses_file
    cat "$script_dir"/$dns_ip_mapping_file >> $parses_file
#    echo "Hosts file: "
#    cat $parses_file
  fi
  # Check and add ldap string
  ldap_string_exist=$(cat < $parses_file|grep "$ldap_string")
  if [ -z "$ldap_string_exist" ]; then
    echo "# --- LDAP SERVER ---" >> $parses_file
    echo $ldap_server >> $parses_file
  fi
    echo "Hosts file: "
    cat $parses_file

#  exit 0
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

if [ "$HOST_EXIST" = false ]; then
  if [ ! -f $DNS_IP_MAPPING_FILE ]; then
    echo -e "${yellow}$DNS_IP_MAPPING_FILE file not found - WARNING${normal}"
    echo -e "Create it,
      or specify -host_exist key (if hosts file already edited),
      or specify -dns_ip_mapping_file key with file path,
      or environment var 'DNS_IP_MAPPING_FILE'${normal}"
    echo -e "${red}The script cannot be executed - ERROR${normal}"
    exit 1
  fi
fi

get_var
sed_var_in_conf
echo -e "\n${yellow}Cat conf...${normal}"
echo
cat $script_dir/$CONF_NAME
echo
echo -e "\n${yellow}Cat $dns_ip_mapping_file...${normal}"
echo
if [ "$HOST_EXIST" = false ]; then
  cat $script_dir/$dns_ip_mapping_file
fi
echo
read -p "Press enter to continue: "
install_dnsmasq
copy_dnsmasq_conf

