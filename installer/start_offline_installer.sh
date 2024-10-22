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
#systems=(
#  "ubuntu"
#  "sberlinux"
#)

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
[[ -z $KEYSTACK_RC_VERSION ]] && KEYSTACK_RC_VERSION=""

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

#select_os () {
#  echo
#  PS3='Select OS: '
#  select os in "${systems[@]}"; do
#      if [[ $REPLY == "0" ]]; then
#          echo 'Bye!' >&2
#          exit 0
#      elif [[ -z $os ]]; then
#          echo 'Invalid choice, try again' >&2
#      else
#        REPLY=$(( $REPLY - 1 ))
#        system=${systems[$REPLY]}
#        echo -e "\nOS selected: "
#        echo -e "$system\n"
#        export SYSTEM=$system
#        break
#      fi
#  done
#}

select_os () {
  # check os release
  os=unknown
  [[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })

  case "$os" in
    ubuntu|sberlinux)
      system=$os
      ;;
#    sberlinux)
#      ;;
    *)
      echo -e "${red}OS $os is not supported - ERROR${normal}"
      exit 1
      ;;
  esac
  export SYSTEM=$system
}

#
#
#  is_ubuntu=$(cat /etc/os-release|grep ubuntu)
#  if [ -n "$is_ubuntu" ]; then
#    SYSTEM="ubuntu"
#  fi
#  is_sberlinux=$(cat /etc/os-release|grep sberlinux)
#  if [ -n "$is_sberlinux" ]; then
#    echo "Installing docker on sberlinux"
#    if bash $script_dir/docker_sberlinux_installation.sh; then
#      return
#    fi
#  fi
#else
#  return
#fi
#echo -e "${red}Failed to install docker - ERROR${normal}"
#exit 1
#}

check_and_install_docker () {
  #Install docker if need
  if ! command -v docker &> /dev/null; then
    is_ubuntu=$(cat /etc/os-release|grep ubuntu)
    if [ -n "$is_ubuntu" ]; then
      echo "Installing docker on ubuntu"
      if bash $script_dir/docker_ubuntu_installation.sh; then
        return
      fi
    fi
    is_sberlinux=$(cat /etc/os-release|grep sberlinux)
    if [ -n "$is_sberlinux" ]; then
      echo "Installing docker on sberlinux"
      if bash $script_dir/docker_sberlinux_installation.sh; then
        return
      fi
    fi
  else
    return
  fi
  echo -e "${red}Failed to install docker - ERROR${normal}"
  exit 1
}

validate_url () {
  if [[ `wget -S --spider $1  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then echo "true"; fi
}

if [ -z "$1" ]; then
  if [ -z "$KEYSTACK_RELEASE" ]; then
    read -rp "Enter KeyStack release [ks2024.3]: " KEYSTACK_RELEASE
  fi
  export KEYSTACK_RELEASE=${KEYSTACK_RELEASE:-"ks2024.3"}
else
  KEYSTACK_RELEASE=$1
  export KEYSTACK_RELEASE=$KEYSTACK_RELEASE
fi

echo -e "
${yellow}WARNING!${normal}
Before continue, make sure you have:
  - DNS (dnsmasq)
  - Self signed certs
  - Remote nexus with with the necessary repositories
"

read -p "Press enter to continue: "

select_os

if [ -z "$SYSTEM" ]; then
  echo -e "${red}\$SYSTEM variable not defined - ERROR${normal}"
  exit 1
fi

# get Release candidate version
if [[ -z "${KEYSTACK_RC_VERSION}" ]]; then
  read -rp "If necessary, specify the release candidate (exp: rc7) version or press Enter : " KEYSTACK_RC_VERSION
fi
export KEYSTACK_RC_VERSION=${KEYSTACK_RC_VERSION:-""}

if [ -n "$KEYSTACK_RC_VERSION" ]; then
  export KEYSTACK_RC_VERSION="$KEYSTACK_RC_VERSION-"
fi

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
  url_valid=$(validate_url $RELEASE_URL)
  if [ "$url_valid" = true ]; then
    wget $RELEASE_URL -P $HOME/
  else
    echo -e "${red}Failed to download from link $RELEASE_URL - ERROR${normal}"
    exit 1
  fi
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
else
  cp $HOME/.ssh/id_rsa_backup $HOME/.ssh/id_rsa
fi

lcm_mgmt_ip=$(ip a|grep mgmt|grep inet|grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,3}' \
  |awk '{p=index($1,"/");print substr($1,0,p-1)}')

export KS_INSTALL_LCM_IP=$lcm_mgmt_ip
echo -e "KS_INSTALL_LCM_IP: $KS_INSTALL_LCM_IP\n"

if [ -d "$HOME/installer" ]; then
  [[ ! -d "$HOME/installer/certs" ]] && { mkdir -p ~/installer/certs; }
  if [ -z "$( ls -A ~/installer/certs )" ]; then
    mkdir -p ~/installer/certs
    check_ssh_to_central_auth=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $CENTRAL_AUTH_SERVICE_IP echo ok 2>&1)
    if [ "$check_ssh_to_central_auth" = ok ]; then
      scp -r $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER $HOME/installer/
    else
      echo -e "${red}No ssh access to $CENTRAL_AUTH_SERVICE_IP - ERROR${normal}"
      exit 1
    fi
  fi
  cd $INIT_INSTALLER_FOLDER
  echo "list of certs in $INIT_INSTALLER_FOLDER/certs folder"
  ls -la ./certs
  echo "Start installer.sh script"
  ./installer.sh| tee $HOME/installer-$(date '+%Y-%m-%d'-%H-%M).log
fi
