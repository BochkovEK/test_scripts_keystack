#!/bin/bash

# Script for deploy nexus to ubuntu\ may be sber linux

#!!! Script сhanging LCM_NEXUS_NAME into $parentdir/self_signed_certs/certs_envs to $REMOTE_NEXUS

REMOTE_NEXUS=remote-nexus

#Script_dir, current folder
script_dir=$(dirname $0)
parentdir="$(dirname "$script_dir")"

source $parentdir/cert_envs

lcm_nexus_name_string=$(cat $parentdir/self_signed_certs/certs_envs|grep -m "LCM_NEXUS_NAME")

sed -i "s/$lcm_nexus_name_string/LCM_NEXUS_NAME=$REMOTE_NEXUS/" $parentdir/self_signed_certs/certs_envs

bash $parentdir/self_signed_certs/generate_self_signed_certs.sh

sed -i "s/DOMAIN/$DOMAIN/g" $script_dir/nginx_https.conf
sed -i "s/LCM_NEXUS_NAME/$LCM_NEXUS_NAME/g" $script_dir/nginx_https.conf

docker compose up -f $script_dir/docker-compose.yaml -d