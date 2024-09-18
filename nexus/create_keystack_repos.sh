#!/bin/bash

#The script created keystack repos by json files

self_signed_certs_folder="self_signed_certs"
#generate_self_signed_certs_script="generate_self_signed_certs.sh"
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

[[ -z $DEBUG ]] && DEBUG="true"
[[ -z $ENV_FILE ]] && ENV_FILE="$self_signed_certs_folder/certs_envs"
[[ -z $NEXUS_USER ]] && NEXUS_USER="admin"
[[ -z $REMOTE_NEXUS_NAME ]] && REMOTE_NEXUS_NAME=""
[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $NEXUS_PORT ]] && NEXUS_PORT="8081"


if [ -f "$parent_dir/$ENV_FILE" ]; then
  echo "$ENV_FILE file exists"
  source $parent_dir/$ENV_FILE
fi

DOCKER_HTTP="http://$REMOTE_NEXUS_NAME.$DOMAIN:$NEXUS_PORT/service/rest/v1/repositories"
password=$(docker exec -it nexus cat /nexus-data/admin.password)

echo -e "
  REMOTE_NEXUS_NAME:  $REMOTE_NEXUS_NAME
  DOMAIN:             $DOMAIN
  DOCKER_HTTP:        $DOCKER_HTTP
  NEXUS_USER:         $NEXUS_USER
  NEXUS_PORT:         $NEXUS_PORT
  password:           $password
"

read -p "Press enter to continue..."

# k-images docker(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/docker/hosted" -d @docker-hosted-k-images.json
# docker-sber yum(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/yum/hosted" -d @yum-hosted-docker-sber.json
# sberlinux yum(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/yum/hosted" -d @yum-hosted-sberlinux.json
# images raw(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @raw-hosted-images.json
# k-add raw(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @raw-hosted-k-add.json
# k-backup raw(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @raw-hosted-k-backup.json
# k-pip pypi(hosted)
curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/pypi/hosted" -d @pypi-hosted-k-pip.json
