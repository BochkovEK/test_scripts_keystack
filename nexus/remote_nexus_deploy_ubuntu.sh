#!/bin/bash

# Script for deploy nexus to ubuntu\ may be sber linux

#!!! Script сhanging LCM_NEXUS_NAME into $parentdir/self_signed_certs/certs_envs to $REMOTE_NEXUS

[[ -z $DEBUG ]] && DEBUG="true"

REMOTE_NEXUS=remote-nexus

#Script_dir, current folder
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
#parentdir=$(dirname "$script_dir")
parentdir=$(builtin cd $script_dir; pwd)

source $parentdir/cert_envs

  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  script_dir: $script_dir
  parentdir: $parentdir
  CERTS_DIR: $CERTS_DIR
  OUTPUT_CERTS_DIR: $OUTPUT_CERTS_DIR
  DOMAIN: $DOMAIN
  CA_IP: $CA_IP
  LCM_NEXUS_NAME: $LCM_NEXUS_NAME
  LCM_GITLAB_NAME: $LCM_GITLAB_NAME
  LCM_VAULT_NAME: $LCM_VAULT_NAME
  LCM_NETBOX_NAME: $LCM_NETBOX_NAME
  "

lcm_nexus_name_string=$(cat $parentdir/self_signed_certs/certs_envs|grep -m "LCM_NEXUS_NAME")

  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  lcm_nexus_name_string: $lcm_nexus_name_string
  REMOTE_NEXUS: $REMOTE_NEXUS
  "
sed -i "s/$lcm_nexus_name_string/LCM_NEXUS_NAME=$REMOTE_NEXUS/" $parentdir/self_signed_certs/certs_envs

bash $parentdir/self_signed_certs/generate_self_signed_certs.sh

sed -i "s/DOMAIN/$DOMAIN/g" $script_dir/nginx_https.conf
sed -i "s/LCM_NEXUS_NAME/$LCM_NEXUS_NAME/g" $script_dir/nginx_https.conf

docker compose up -f $script_dir/docker-compose.yaml -d