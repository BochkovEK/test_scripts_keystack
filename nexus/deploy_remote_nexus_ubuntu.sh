#!/bin/bash

# Script for deploy nexus to ubuntu\ may be sber linux

# Before nexus deploy:
# 1) Change vi $HOME/test_scripts_keystack/self_signed_certs/certs_envs
# 2) Generate certs in $HOME/certs: bash $HOME/test_scripts_keystack/self_signed_certs/generate_self_signed_certs.sh
# After nexus deploy copy $HOME/certs to $HOME/installer/ on lcm:
# scp -r $HOME/certs $lcm:$HOME/installer/

#!!! docker exec -it nexus cat /nexus-data/admin.password

[[ -z $DEBUG ]] && DEBUG="true"

#REMOTE_NEXUS=remote-nexus

#Script_dir, current folder
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parentdir=$(dirname "$script_dir")
#parentdir=$(builtin cd $script_dir; pwd)

#Install docker if need
if ! command -v docker &> /dev/null; then
  is_ubuntu=$(cat /etc/os-release|grep ubuntu)
  if [ -n "$is_ubuntu" ]; then
    echo "Installing docker on ubuntu"
    bash $script_dir/docker_ubuntu_installation.sh
  fi
fi

source $parentdir/self_signed_certs/certs_envs

  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  script_dir: $script_dir
  parentdir: $parentdir
  CERTS_DIR: $CERTS_DIR
  OUTPUT_CERTS_DIR: $OUTPUT_CERTS_DIR
  DOMAIN: $DOMAIN
  CA_IP: $CA_IP
  LCM_NEXUS_NAME: $LCM_NEXUS_NAME
  REMOTE_NEXUS_NAME: $REMOTE_NEXUS_NAME
  LCM_GITLAB_NAME: $LCM_GITLAB_NAME
  LCM_VAULT_NAME: $LCM_VAULT_NAME
  LCM_NETBOX_NAME: $LCM_NETBOX_NAME
  "

#Change in envs LCM_NEXUS_NAME var
#lcm_nexus_name_string=$(cat $parentdir/self_signed_certs/certs_envs|grep -m 1 "LCM_NEXUS_NAME")

#  [ "$DEBUG" = true ] && echo -e "
#  [DEBUG]
#  lcm_nexus_name_string: $lcm_nexus_name_string
#  REMOTE_NEXUS: $REMOTE_NEXUS
#  "
#sed -i "s/$lcm_nexus_name_string/export LCM_NEXUS_NAME=$REMOTE_NEXUS/" $parentdir/self_signed_certs/certs_envs

echo "Sourcing envs after sed"
source $parentdir/self_signed_certs/certs_envs

#Add string to hosts
nexus_string_exists=$(cat /etc/hosts|grep $REMOTE_NEXUS_NAME)
if [ -z "$nexus_string_exists" ]; then
  sed -i "s/127.0.0.1 localhost/127.0.0.1 localhost $REMOTE_NEXUS_NAME.$DOMAIN/" /etc/hosts
fi

#Generating certs
bash $parentdir/self_signed_certs/generate_self_signed_certs.sh

#Change nginx conf
echo "Changing nginx conf..."
sed -i "s/DOMAIN/$DOMAIN/g" $script_dir/nginx_https.conf
sed -i "s/LCM_NEXUS_NAME/$REMOTE_NEXUS_NAME/g" $script_dir/nginx_https.conf
#sed -i -e "s@OUTPUT_CERTS_DIR@$OUTPUT_CERTS_DIR@g" $script_dir/nginx_https.conf

#Conatiners up
docker compose -f $script_dir/docker-compose.yaml up -d