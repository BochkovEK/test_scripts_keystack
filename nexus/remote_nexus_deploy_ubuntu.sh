#!/bin/bash

# Script for deploy nexus to ubuntu\ may be sber linux

#!!! Change LCM_NEXUS_NAME into $parentdir/self_signed_certs/certs_envs to "remote-nexus"

#Script_dir, current folder
script_dir=$(dirname $0)
parentdir="$(dirname "$script_dir")"

source $parentdir/cert_envs

bash $parentdir/self_signed_certs/generate_self_signed_certs.sh

sed -i "s/DOMAIN/$DOMAIN/g" $script_dir/nginx_https.conf
sed -i "s/LCM_NEXUS_NAME/$LCM_NEXUS_NAME/g" $script_dir/nginx_https.conf

docker compose up -f $script_dir/docker-compose.yaml -d