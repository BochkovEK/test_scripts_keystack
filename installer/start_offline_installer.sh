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
utils_dir=$parent_dir/utils
installer_conf_folder="installer_conf"
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
[[ -z $KEYSTACK_RELEASE ]] && KEYSTACK_RELEASE=""

if [ -z "$1" ]; then
  if [ -z "$KEYSTACK_RELEASE" ]; then
    echo -e "${red}To run this script, you need to define keystack release as parameter or env var KEYSTACK_RELEASE - ERROR${normal}"
    exit 1
  fi
else
  KEYSTACK_RELEASE=$1
fi

select_config_file () {
  env_files="$script_dir/$KEYSTACK_RELEASE/$installer_conf_folder/*"
#  search_dir=./ks2024.2.5/installer_conf/*
  for file in $env_files; do
#    echo "$file"
    files+=("$file")
  done

  PS3='Select installer config file or 0 to exit: '
  select file in "${files[@]}"; do
      if [[ $REPLY == "0" ]]; then
          echo 'Bye!' >&2
          exit 0
      elif [[ -z $file ]]; then
          echo 'Invalid choice, try again' >&2
      else
        REPLY=$(( $REPLY - 1 ))
        config_file=${files[$REPLY]}
        echo -e "\nInstaller config selected:"
        echo -e "$config_file\n"
        break
      fi
  done
  source $config_file
  # use scp to upload "$file" here
}

echo -e "
${yellow}WARNING!${normal}
Before continue, make sure you have:
  - DNS (dnsmasq)
  - Self signed certs
  - Remote nexus with with the necessary repositories
"

read -p "Press enter to continue: "

installer_envs=$script_dir/$KEYSTACK_RELEASE/$start_installer_envs

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

select_config_file

if [ ! -f "$HOME/.ssh/id_rsa_backup" ]; then
  cp $HOME/.ssh/id_rsa $HOME/.ssh/id_rsa_backup
fi

lcm_mgmt_ip=$(ip a|grep mgmt|grep inet|grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,3}' \
  |awk '{p=index($1,"/");print substr($1,0,p-1)}')

export KS_INSTALL_LCM_IP=$lcm_mgmt_ip
echo -e "KS_INSTALL_LCM_IP: $KS_INSTALL_LCM_IP\n"

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
