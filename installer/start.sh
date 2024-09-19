#!/bin/bash

# The script start installer

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

[[ -z $CENTRAL_AUTH_SERVICE_IP ]] && CENTRAL_AUTH_SERVICE_IP="ebochkov-keystack-add_vm-01"
[[ -z $CERTS_FOLDER ]] && CERTS_FOLDER="$HOME/certs"
[[ -z $RELEASE_URL ]] && RELEASE_URL="https://repo.itkey.com/repository/k-install/installer-ks2024.3-rc1-sberlinux-offline.tgz"
[[ -z $INSTALLER_CONF ]] && INSTALLER_CONF="Client_certs_Nexus_LDAP_Gitlab_Netbox_installer_envs"


bash $parent_dir/utils/install_wget.sh
wget $RELEASE_URL -P $HOME/
tar -xf $HOME/*.tgz -C $HOME/
cp -r ~/installer ~/installer_backup
source $script_dir/$INSTALLER_CONF
cp $HOME/.ssh/id_rsa $HOME/.ssh/id_rsa_backup
lcm_mgmt_ip=$(ip a|grep mgmt|grep inet|grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,3}' \
  |awk '{p=index($1,"/");print substr($1,0,p-1)}')
export KS_INSTALL_LCM_IP=$lcm_mgmt_ip

if [ -d "$HOME/installer" ]; then
  scp -r $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER $HOME/installer/
  cd $HOME/installer/
  ls -la ./certs
  ./installer.sh| tee $HOME/installer-$(date '+%Y-%m-%d'-%H-%M).log
fi
