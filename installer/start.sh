#!/bin/bash

# The script start installer

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

[[ -z $CENTRAL_AUTH_SERVICE_IP ]] && CENTRAL_AUTH_SERVICE_IP="ebochkov-keystack-add_vm-01"
[[ -z $CERTS_FOLDER ]] && CERTS_FOLDER="$HOME/certs"
[[ -z $RELEASE_URL ]] && RELEASE_URL="https://repo.itkey.com/repository/k-install/installer-ks2024.3-rc1-sberlinux-offline.tgz"
[[ -z $INSTALLER_CONF ]] && INSTALLER_CONF="Client_certs_Nexus_LDAP_Gitlab_Netbox_installer_envs"
[[ -z $INIT_INSTALLER_FOLDER ]] && INIT_INSTALLER_FOLDER="$HOME/installer"
[[ -z $INIT_INSTALLER_BACKUP_FOLDER ]] && INIT_INSTALLER_BACKUP_FOLDER="$HOME/installer_backup"

bash $parent_dir/utils/install_wget.sh
release_tar=$(echo "${RELEASE_URL##*/}")
echo "release_tar: $release_tar"
if [ ! -f ~/$release_tar ]; then
  wget $RELEASE_URL -P $HOME/
fi
if [ ! -d $INIT_INSTALLER_FOLDER ]; then
  if [ ! -d $INIT_INSTALLER_BACKUP_FOLDER ]; then
    echo "Untar installer archive..."
    tar -xf $HOME/*.tgz -C $HOME/
  else
    echo "Copy init installer folder from backup folder"
    cp -r $INIT_INSTALLER_BACKUP_FOLDER $INIT_INSTALLER_FOLDER
  fi
fi
if [ ! -d "$HOME/installer_backup" ]; then
  echo "Create backup folder"
  cp -r ~/installer ~/installer_backup
fi

source $script_dir/$INSTALLER_CONF

if [ ! -f "$HOME/.ssh/id_rsa_backup" ]; then
  cp $HOME/.ssh/id_rsa $HOME/.ssh/id_rsa_backup
fi

lcm_mgmt_ip=$(ip a|grep mgmt|grep inet|grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,3}' \
  |awk '{p=index($1,"/");print substr($1,0,p-1)}')

export KS_INSTALL_LCM_IP=$lcm_mgmt_ip
echo $KS_INSTALL_LCM_IP

if [ -d "$HOME/installer" ]; then
  if [ -z "$( ls -A ~/installer/certs )" ]; then
    scp -r $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER $HOME/installer/
  fi
  cd $HOME/installer/
  ls -la ./certs
  ./installer.sh| tee $HOME/installer-$(date '+%Y-%m-%d'-%H-%M).log
fi
