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
required_containers_list=(
"nginx"
"nexus"
)

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

deploy_error () {
  echo -e "${red}Nexus deploy - error!${normal}"
  exit 1
}

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
  read -p "Press enter to continue: "
}

waiting_for_nexus_readiness () {
  echo -n Waiting for Nexus readiness...
  while [ "$(curl -isf --cacert "$CERTS_DIR"/ca.crt https://"$REMOTE_NEXUS_NAME"."$DOMAIN"/service/rest/v1/status | awk 'NR==1 {print $2}')"  != "200" ]; do
    echo -n .; sleep 5
  done
  echo .
  echo -e "${green}Nexus is Ready!${normal}"

  echo -e "${yellow}\nTo get initial nexus admin password:${normal}"
  echo "docker exec -it nexus cat /nexus-data/admin.password"
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

check_running_containers () {
    running_container_list=$(docker ps --format "{{.Names}}" --filter status=running)
  for container_required in "${required_containers_list[@]}"; do
    container_running="false"
    for container in $running_container_list; do
#      echo "$container" - "$container_required"
      if [ "$container" = "$container_required" ]; then
        container_running="true"
      fi
    done
    if [ "$container_running" = "true" ]; then
      echo -e "${green}$container_required - ok${normal}"
    else
      echo -e "${red}$container_required - error${normal}"
      deploy_error
    fi
  done
  echo -e "${green}Nexus already deployed${normal}"
  waiting_for_nexus_readiness
  exit 0
}

check_started_containers () {
  started_container_list=$(docker ps --format "{{.Names}}")
  started_containers_count=0
  for container_required in "${required_containers_list[@]}"; do
#    containers_for_nexus_not_running="true"
    for container in $started_container_list; do
#      echo "$container" - "$container_required"
      if [ "$container" = "$container_required" ]; then
        container_exist="true"
      fi
    done
    if [ "$container_exist" = "true" ]; then
      started_containers_count=$((started_containers_count + 1))
    fi
  done
  if ((started_containers_count == 2)); then
    check_running_containers
  elif ((started_containers_count == 0)); then
    return
  else
    echo -e "${yellow}There may have already been a failed Nexus deployment${normal}"
    deploy_error
  fi
}

nexus_docker_up () {
   #Conatiners up
  docker compose -f $script_dir/docker-compose.yaml up -d
}

nexus_bootstarp () {

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

nexus_bootstarp
check_started_containers
nexus_docker_up
waiting_for_nexus_readiness