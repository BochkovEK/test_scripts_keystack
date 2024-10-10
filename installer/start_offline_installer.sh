#!/bin/bash

# The script start installer
# To start script define keystack release as parameter
# Before starting, make sure you have:
#  - DNS (dnsmasq)
#  - Self signed certs
#  - Remote nexus with with the necessary repositories
# Example command: bash start.sh ks2024.3

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$script_dir/utils
start_installer_envs="start_installer_envs"
install_wget_script="install_wget.sh"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $CENTRAL_AUTH_SERVICE_IP ]] && CENTRAL_AUTH_SERVICE_IP=""
[[ -z $CERTS_FOLDER ]] && CERTS_FOLDER="$HOME/certs"
[[ -z $RELEASE_URL ]] && RELEASE_URL=""
[[ -z $INSTALLER_CONF ]] && INSTALLER_CONF=""
[[ -z $INIT_INSTALLER_FOLDER ]] && INIT_INSTALLER_FOLDER="$HOME/installer"
[[ -z $INIT_INSTALLER_BACKUP_FOLDER ]] && INIT_INSTALLER_BACKUP_FOLDER="$HOME/installer_backup"

[ -z $1 ] && { echo -e "${red}To run the script, you need to define keystack release as parameter - ERROR${normal}"; exit 1; }
release_tag=$1

echo -e "
${yellow}WARNING!${normal}
Before continue, make sure you have:
  - DNS (dnsmasq)
  - Self signed certs
  - Remote nexus with with the necessary repositories
"

read -p "Press enter to continue"

installer_envs=$script_dir/$release_tag/$start_installer_envs

if [ -f $installer_envs ]; then
  source $installer_envs
else
  echo -e "${red}Environment variables file \'$installer_envs\' not found - ERROR${normal}"
  exit 1
fi

bash $utils_dir/$install_wget_script
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
echo "KS_INSTALL_LCM_IP: $KS_INSTALL_LCM_IP"

if [ -d "$HOME/installer" ]; then
  if [ -z "$( ls -A ~/installer/certs )" ]; then
    scp -r $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER $HOME/installer/
  fi
  cd $INIT_INSTALLER_FOLDER
  echo "list of certs in $INIT_INSTALLER_FOLDER/certs folder"
  ls -la ./certs
  echo "Start installer.sh script"
  ./installer.sh| tee $HOME/installer-$(date '+%Y-%m-%d'-%H-%M).log
fi
