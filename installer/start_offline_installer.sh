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
script_installer_envs="script_installer_envs"
#start_installer_envs="start_installer_envs"
#install_wget_script="install_wget.sh"
install_package_script="install_package.sh"
add_vm="qa-stable-ubuntu-add_vm-01"
#local_certs_folder="$HOME/certs"
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
[[ -z $SCRIPT_INSTALLER_ENVS ]] && SCRIPT_INSTALLER_ENVS=$script_dir/$script_installer_envs
[[ -z $INIT_INSTALLER_FOLDER ]] && INIT_INSTALLER_FOLDER="$HOME/installer"
[[ -z $INIT_INSTALLER_BACKUP_FOLDER ]] && INIT_INSTALLER_BACKUP_FOLDER="$HOME/installer_backup"
[[ -z $KEYSTACK_RELEASE ]] && KEYSTACK_RELEASE=""
#[[ -z $KEYSTACK_RC_VERSION ]] && KEYSTACK_RC_VERSION=""

source_envs () {

#  installer_envs=$SCRIPT_INSTALLER_ENVS

  echo "Try to source $SCRIPT_INSTALLER_ENVS"

  if [ -f $SCRIPT_INSTALLER_ENVS ]; then
    source $SCRIPT_INSTALLER_ENVS
  else
    echo -e "${yellow}Env file $SCRIPT_INSTALLER_ENVS not exists${normal}"
  fi
}

get_init_vars () {

#  if [ -f $SCRIPT_INSTALLER_ENVS ]; then
#    source $SCRIPT_INSTALLER_ENVS
#  fi
   # check KEYSTACK_RELEASE SYSTEM vars
  [[ -z "${KEYSTACK_RELEASE}" ]] && { echo -e "${red}env KEYSTACK_RELEASE not define - ERROR${normal}"; exit 1; }
#  [[ -z "${KEYSTACK_RC_VERSION}" ]] && { echo -e "${red}env KEYSTACK_RC_VERSION not define - ERROR${normal}"; exit 1; }
  [[ -z "${SYSTEM}" ]] && { echo -e "${red}env SYSTEM not define - ERROR${normal}"; exit 1; }

  # get RELEASE_URL
  if [[ -z "${RELEASE_URL}" ]]; then
    read -rp "Enter release download url [https://repo.itkey.com/repository/k-install/installer-$KEYSTACK_RELEASE-$SYSTEM-offline.tgz]: " RELEASE_URL
  fi
  export RELEASE_URL=${RELEASE_URL:-"https://repo.itkey.com/repository/k-install/installer-$KEYSTACK_RELEASE-$KEYSTACK_RC_VERSION$SYSTEM-offline.tgz"}
  [[ -z "${RELEASE_URL}" ]] && { echo -e "${red}env RELEASE_URL not define - ERROR${normal}"; exit 1; }

#  # get INIT_INSTALLER_FOLDER
#  if [[ -z "${INIT_INSTALLER_FOLDER}" ]]; then
#    read -rp "Enter region name [$HOME/installer]: " INIT_INSTALLER_FOLDER
#  fi
#  export INIT_INSTALLER_FOLDER=${INIT_INSTALLER_FOLDER:-"$HOME/installer"}
#  [[ -z "${INIT_INSTALLER_FOLDER}" ]] && { echo -e "${red}env INIT_INSTALLER_FOLDER not define - ERROR${normal}"; exit 1; }

#   # get INIT_INSTALLER_BACKUP_FOLDER
#  if [[ -z "${INIT_INSTALLER_BACKUP_FOLDER}" ]]; then
#    read -rp "Enter region name [$HOME/installer_backup]: " INIT_INSTALLER_BACKUP_FOLDER
#  fi
#  export INIT_INSTALLER_BACKUP_FOLDER=${INIT_INSTALLER_BACKUP_FOLDER:-"$HOME/installer_backup"}
#  [[ -z "${INIT_INSTALLER_BACKUP_FOLDER}" ]] && { echo -e "${red}env INIT_INSTALLER_BACKUP_FOLDER not define - ERROR${normal}"; exit 1; }

#  # get domain
#  if [[ -z "${KS_INSTALL_DOMAIN}" ]]; then
#    read -rp "Enter domain [test.domain]: " KS_INSTALL_DOMAIN
#  fi
#  export KS_INSTALL_DOMAIN=${KS_INSTALL_DOMAIN:-"test.domain"}
#  [[ -z "${KS_INSTALL_DOMAIN}" ]] && { echo -e "${red}env KS_INSTALL_DOMAIN not define - ERROR${normal}"; exit 1; }

  # get CENTRAL_AUTH_SERVICE_IP
  if [[ -z "${CENTRAL_AUTH_SERVICE_IP}" ]]; then
    read -rp "Enter central auth service ip or fqdn where is the catalog with certificates (\$HOME/certs) [$add_vm]: " CENTRAL_AUTH_SERVICE_IP
  fi
  export CENTRAL_AUTH_SERVICE_IP=${CENTRAL_AUTH_SERVICE_IP:-"$add_vm"}
  [[ -z "${CENTRAL_AUTH_SERVICE_IP}" ]] && { echo -e "${red}env CENTRAL_AUTH_SERVICE_IP not define - ERROR${normal}"; exit 1; }

  echo -E "
    KEYSTACK_RELEASE:               $KEYSTACK_RELEASE
    RELEASE_URL:                    $RELEASE_URL
    CENTRAL_AUTH_SERVICE_IP:        $CENTRAL_AUTH_SERVICE_IP
  "
#    SYSTEM:                         $SYSTEM
#    INIT_INSTALLER_FOLDER:          $INIT_INSTALLER_FOLDER
#    INIT_INSTALLER_BACKUP_FOLDER:   $INIT_INSTALLER_BACKUP_FOLDER
#    KS_INSTALL_DOMAIN:              $KS_INSTALL_DOMAIN
#    KEYSTACK_RC_VERSION:            $KEYSTACK_RC_VERSION

  if [ ! -f $SCRIPT_INSTALLER_ENVS ]; then
    echo "
export KEYSTACK_RELEASE=$KEYSTACK_RELEASE
export RELEASE_URL=$RELEASE_URL
export CENTRAL_AUTH_SERVICE_IP=$CENTRAL_AUTH_SERVICE_IP
    " > $SCRIPT_INSTALLER_ENVS
  fi
#export KEYSTACK_RC_VERSION=$KEYSTACK_RC_VERSION
#export SYSTEM=$SYSTEM
#export INIT_INSTALLER_FOLDER=$INIT_INSTALLER_FOLDER
#export KS_INSTALL_DOMAIN=$KS_INSTALL_DOMAIN
#export INIT_INSTALLER_BACKUP_FOLDER=$INIT_INSTALLER_BACKUP_FOLDER

  read -p "Press enter to continue: "
}

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

  # check KS_SELF_SIG
  if [[ -z "${KS_SELF_SIG}" ]]; then
    read -rp "Will self-signed certificates be used during installation y/n [y]: " KS_SELF_SIG
  fi
  export KS_SELF_SIG=${KS_SELF_SIG:-"y"}
  [[ -z "${KS_SELF_SIG}" ]] && { echo -e "${red}env KS_SELF_SIG not define - ERROR${normal}"; exit 1; }

  if [ "$KS_SELF_SIG" = n ]; then
      # get Central Authentication Service ip
    if [[ -z "${CENTRAL_AUTH_SERVICE_IP}" ]]; then
      read -rp "Enter Central Authentication Service server IP: " CENTRAL_AUTH_SERVICE_IP
    fi
    export CENTRAL_AUTH_SERVICE_IP=$CENTRAL_AUTH_SERVICE_IP
    [[ -z "${CENTRAL_AUTH_SERVICE_IP}" ]] && { echo -e "${red}env CENTRAL_AUTH_SERVICE_IP not define - ERROR${normal}"; exit 1; }

    # get CERTS_FOLDER
    if [[ -z "${CERTS_FOLDER}" ]]; then
      read -rp "Enter certs folder on Central Authentication Service server [$HOME/certs]: " CERTS_FOLDER
    fi
    export CERTS_FOLDER=${CERTS_FOLDER:-"$HOME/certs"}
    echo -E "
  CENTRAL_AUTH_SERVICE_IP:        $CENTRAL_AUTH_SERVICE_IP
  CERTS_FOLDER:                   $CERTS_FOLDER
    "
  fi

  if [[ -z "${KS_CLIENT_NEXUS}" ]]; then
    read -rp "remote\existing Artifactory y/n [n]: " KS_CLIENT_NEXUS
  fi
  export KS_CLIENT_NEXUS=${KS_CLIENT_NEXUS:-"n"}
  [[ -z "${KS_CLIENT_NEXUS}" ]] && { echo -e "${red}env KS_CLIENT_NEXUS not define - ERROR${normal}"; exit 1; }
  if [ "$KS_CLIENT_NEXUS" = y ]; then
    if [[ -z "${KS_CLIENT_NEXUS_PASSWORD}" ]]; then
      read -rp "Enter the remote\existing Artifactory password(at least 8 characters): " KS_CLIENT_NEXUS_PASSWORD
    fi
    export KS_CLIENT_NEXUS_PASSWORD=$KS_CLIENT_NEXUS_PASSWORD
    [[ -z "${KS_CLIENT_NEXUS_PASSWORD}" ]] && { echo -e "${red}env KS_CLIENT_NEXUS_PASSWORD not define - ERROR${normal}"; exit 1; }
    echo -E "
  KS_CLIENT_NEXUS_PASSWORD:   $KS_CLIENT_NEXUS_PASSWORD
    "
  fi
  read -p "Press enter to continue: "
}

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
  if [ -z "$SYSTEM" ]; then
    echo -e "${red}\$SYSTEM variable not defined - ERROR${normal}"
   exit 1
  fi
}

validate_url () {
  if [[ `wget -S --spider $1  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then echo "true"; fi
}

#check_ssh_connection () {
#
#}

# WARNING
echo -e "
${yellow}WARNING!${normal}
Before continue, make sure you have:
  - DNS (dnsmasq)
  - Self signed certs ($CERTS_FOLDER)
  - LDAP cert ($CERTS_FOLDER/ldaps.pem)
  - Remote nexus with the necessary repositories
"
read -p "Press enter to continue: "

# Get KEYSTACK_RELEASE
#if [ -n "$1" ]; then
##  if [ ! -f $SCRIPT_INSTALLER_ENVS ]; then
#    if [ -z "$KEYSTACK_RELEASE" ]; then
#
#      read -rp "Enter KeyStack release [$ks2024.3]: " KEYSTACK_RELEASE
##    fi
#    export KEYSTACK_RELEASE=${KEYSTACK_RELEASE:-"ks2024.3"}
##  else
##    source $SCRIPT_INSTALLER_ENVS
#  fi
#else
#  KEYSTACK_RELEASE=$1
#  export KEYSTACK_RELEASE=$KEYSTACK_RELEASE
#fi

## Get Release candidate version
#if [[ -z "${KEYSTACK_RC_VERSION}" ]]; then
#  read -rp "If necessary, specify the release candidate (exp: rc7) version or press Enter : " KEYSTACK_RC_VERSION
#fi
##export KEYSTACK_RC_VERSION=${KEYSTACK_RC_VERSION:-""}
#
#if [ -n "$KEYSTACK_RC_VERSION" ]; then
#  export KEYSTACK_RC_VERSION="$KEYSTACK_RC_VERSION-"
#fi

select_os
source_envs
get_init_vars


bash $utils_dir/$install_package_script wget
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
  echo "Create backup folder..."
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

    for i in {1...5}; do
      echo -e "${yellow}Try to check ssh to $CENTRAL_AUTH_SERVICE_IP [$i]${normal}"
      check_ssh_to_central_auth=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $CENTRAL_AUTH_SERVICE_IP echo ok 2>&1)
      if [ "$check_ssh_to_central_auth" = ok ]; then
        echo -e "${yellow}Copying certs from $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER to $HOME/installer/${normal}"
        if ! scp -r $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER $HOME/installer/; then
#          echo "Ошибка копирования! Код выхода: $?"
          cp -r $CERTS_FOLDER/ $HOME/installer/
        fi
#        scp -r $CENTRAL_AUTH_SERVICE_IP:$CERTS_FOLDER $HOME/installer/
        break
      fi
      sleep 1
    done

    if [ ! "$check_ssh_to_central_auth" = ok ]; then
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
