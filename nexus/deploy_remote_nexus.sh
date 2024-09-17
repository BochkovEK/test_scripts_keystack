#!/bin/bash

# Script for deploy nexus to ubuntu\ may be sber linux

# Remote nexus deploy
# 1) Change certs_envs:
# vi $HOME/test_scripts_keystack/self_signed_certs/certs_envs
# 2) Source envs:
# source $HOME/test_scripts_keystack/self_signed_certs/certs_envs
# 3) Generate certs in $HOME/certs:
# bash $HOME/test_scripts_keystack/self_signed_certs/generate_self_signed_certs.sh
# 4) Deploy nexus:
# bash $HOME/test_scripts_keystack/deploy_remote_nexus.sh
# 5) For installer.sh use remote nexus copy $HOME/certs to $HOME/installer/ on lcm:
# scp -r $HOME/certs $lcm:$HOME/installer/

#!!! docker exec -it nexus cat /nexus-data/admin.password

green=`tput setaf 2`
yellow=`tput setaf 3`
red=`tput setaf 1`
normal=`tput sgr0`

self_signed_certs_folder="self_signed_certs"
generate_self_signed_certs_script="generate_self_signed_certs.sh"

[[ -z $DEBUG ]] && DEBUG="true"
[[ -z $ENV_FILE ]] && ENV_FILE="$self_signed_certs_folder/certs_envs"

#Script_dir, current folder
script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
#parentdir=$(builtin cd $script_dir; pwd)


while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      Remote nexus deploy
        1) Change certs_envs:
          vi $HOME/test_scripts_keystack/self_signed_certs/certs_envs
        2) Deploy nexus:
          bash $HOME/test_scripts_keystack/nexus/deploy_remote_nexus.sh
        3) For installer.sh use remote nexus copy $HOME/certs to $HOME/installer/ on lcm:
          scp -r $HOME/certs \$lcm:$HOME/installer/

      Add keys:
        --debug       - enable debug
      "
      exit 0
      break ;;
    --debug) DEBUG="true"
      shift ;;
    --) shift
      break ;;
    *) echo "$1 is not an option";;
  esac
  shift
done


get_init_vars () {


if [ -f "$parent_dir/$ENV_FILE" ]; then
  echo "$ENV_FILE file exists"
  source $parent_dir/$ENV_FILE
fi

# get Central Authentication Service folder
  if [[ -z "${CERTS_DIR}" ]]; then
    read -rp "Enter Central Authentication Service folder [$HOME/central_auth_service]: " CERTS_DIR
  fi
  export CERTS_DIR=${CERTS_DIR:-"$HOME/central_auth_service"}

  # get Output certs folder
  if [[ -z "${OUTPUT_CERTS_DIR}" ]]; then
    read -rp "Enter certs output folder for installer [$HOME/certs]: " OUTPUT_CERTS_DIR
  fi
  export OUTPUT_CERTS_DIR=${OUTPUT_CERTS_DIR:-"$HOME/certs"}

# get domain name
if [[ -z "${DOMAIN}" ]]; then
  read -rp "Enter certs output folder for installer [test.domain]: " DOMAIN
fi
export DOMAIN=${DOMAIN:-"test.domain"}

# get Remote Nexus domain nama
if [[ -z "${REMOTE_NEXUS_NAME}" ]]; then
  read -rp "Enter the Remote Nexus domain name [remote-nexus]: " REMOTE_NEXUS_NAME
fi
export REMOTE_NEXUS_NAME=${REMOTE_NEXUS_NAME:-"remote-nexus"}

echo -E "
envs list:
  script_dir:         $script_dir
  parent_dir:         $parent_dir
  CERTS_DIR:          $CERTS_DIR
  DOMAIN:             $DOMAIN
  REMOTE_NEXUS_NAME:  $REMOTE_NEXUS_NAME
"
}

#Checking if directory $CERTS_DIR and $OUTPUT_CERTS_DIR are empty
check_certs_for_nexus () {
  certs_for_nexus_exists="false"
  echo "Checking if directory $CERTS_DIR and $OUTPUT_CERTS_DIR are empty..."
  if [ -f $OUTPUT_CERTS_DIR/$REMOTE_NEXUS_NAME.$DOMAIN.pem ]; then
    printf "%s\n" "${green}Certs for remote nexus: $REMOTE_NEXUS_NAME.$DOMAIN in folder OUTPUT_CERTS_DIR: \
$OUTPUT_CERTS_DIR! already exists - ok!${normal}"
     certs_for_nexus_exists="true"
  else
    printf "%s\n" "${yellow}Certs for remote nexus: $REMOTE_NEXUS_NAME.$DOMAIN in folder OUTPUT_CERTS_DIR: \
$OUTPUT_CERTS_DIR! not exists!${normal}"
    printf "%s\n" "${yellow}Start script $generate_self_signed_certs_script...${normal}"
    bash $parent_dir/$self_signed_certs_folder/$generate_self_signed_certs_script
  fi
}

deploy_remote_nexus () {
  echo "Deploy Remote-Nexus..."

  read -p "Press enter to continue: "
  #Install docker if need
  if ! command -v docker &> /dev/null; then
    is_ubuntu=$(cat /etc/os-release|grep ubuntu)
    if [ -n "$is_ubuntu" ]; then
      echo "Installing docker on ubuntu"
      bash $script_dir/docker_ubuntu_installation.sh
    fi
    is_sberlinux=$(cat /etc/os-release|grep sberlinux)
    if [ -n "$is_sberlinux" ]; then
      echo "Installing docker on sberlinux"
      bash $script_dir/docker_sberlinux_installation.sh
    fi
  fi


  #Change in envs LCM_NEXUS_NAME var
  #lcm_nexus_name_string=$(cat $parentdir/self_signed_certs/certs_envs|grep -m 1 "LCM_NEXUS_NAME")

  #  [ "$DEBUG" = true ] && echo -e "
  #  [DEBUG]
  #  lcm_nexus_name_string: $lcm_nexus_name_string
  #  REMOTE_NEXUS: $REMOTE_NEXUS
  #  "
  #sed -i "s/$lcm_nexus_name_string/export LCM_NEXUS_NAME=$REMOTE_NEXUS/" $parentdir/self_signed_certs/certs_envs

  #echo "Sourcing envs after sed"
  #source $parentdir/self_signed_certs/certs_envs

  #Add string to hosts
  nexus_string_exists=$(cat /etc/hosts|grep $REMOTE_NEXUS_NAME)
  if [ -z "$nexus_string_exists" ]; then
    sed -i "s/127.0.0.1 localhost/127.0.0.1 localhost $REMOTE_NEXUS_NAME.$DOMAIN/" /etc/hosts
  fi


  #Change nginx conf
  echo "Changing nginx conf..."
  sed -i "s/DOMAIN/$DOMAIN/g" $script_dir/nginx_https.conf
  sed -i "s/LCM_NEXUS_NAME/$REMOTE_NEXUS_NAME/g" $script_dir/nginx_https.conf
  #sed -i -e "s@OUTPUT_CERTS_DIR@$OUTPUT_CERTS_DIR@g" $script_dir/nginx_https.conf


  #Conatiners up
  docker compose -f $script_dir/docker-compose.yaml up -d


  echo "${yellow}To get initial nexus admin password:${reset}"
  echo "docker exec -it nexus cat /nexus-data/admin.password"
}


get_init_vars
check_certs_for_nexus

if [ "$certs_for_nexus_exists" = false ]; then
  check_certs_for_nexus
  if [ "$certs_for_nexus_exists" = false ]; then
    printf "%s\n" "${red}Nexus can not be deploy without certs - error${normal}"
    exit 1
  fi
fi

deploy_remote_nexus

