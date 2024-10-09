#!/bin/bash

#The script created keystack repos by json files
# To start script define keystack release as parameter
# Example command: bash create_keystack_repos.sh ks2024.3


self_signed_certs_folder="self_signed_certs"
#generate_self_signed_certs_script="generate_self_signed_certs.sh"
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)


[[ -z $DEBUG ]] && DEBUG="true"
[[ -z $ENV_FILE ]] && ENV_FILE="$self_signed_certs_folder/certs_envs"
[[ -z $NEXUS_USER ]] && NEXUS_USER="admin"
[[ -z $REMOTE_NEXUS_NAME ]] && REMOTE_NEXUS_NAME=""
[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $NEXUS_PORT ]] && NEXUS_PORT="8081"
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"

[ -z $1 ] && { echo -e "${red}To run the script, you need to define keystack release as parameter - ERROR${normal}"; exit 1; }
release_tag=$1

if [ -f "$parent_dir/$ENV_FILE" ]; then
  echo "$ENV_FILE file exists"
  source $parent_dir/$ENV_FILE
else
  echo -e "${red}Environment variables file \'$installer_envs\' not found - ERROR${normal}"
  exit 1
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

repos_json_files=$(ls -f $script_dir/$release_tag/*.json|sed -E s#.+/##)
# example output
#docker-hosted-k-images.json
#pypi-hosted-k-pip.json
#raw-hosted-images.json
#raw-hosted-k-add.json
#raw-hosted-k-backup.json
#yum-hosted-docker-sberlinux.json
#yum-hosted-sberlinux.json

for repo in repos_json_files; do
  type=$(echo $repo|awk 'BEGIN {FS="-";}{print $1}')
  sub_type=$(echo $repo|awk 'BEGIN {FS="-";}{print $1}')

  "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: type: $type
  [DEBUG]: sub_type: $sub_type
"

  echo "curl -v -u $NEXUS_USER:$password -H \"Connection: close\" -H \"Content-Type: application/json\" -X POST \"$DOCKER_HTTP/$type/$sub_type\" -d @$script_dir/$release_tag/$repo"

done

read -p "Press enter to continue..."
echo foo
exit 0



## k-images docker(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/docker/hosted" -d @$script_dir/docker-hosted-k-images.json
## docker-sber yum(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/yum/hosted" -d @$script_dir/yum-hosted-docker-sberlinux.json
## sberlinux yum(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/yum/hosted" -d @$script_dir/yum-hosted-sberlinux.json
## images raw(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @$script_dir/raw-hosted-images.json
## k-add raw(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @$script_dir/raw-hosted-k-add.json
## k-backup raw(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @$script_dir/raw-hosted-k-backup.json
## k-pip pypi(hosted)
#curl -v -u $NEXUS_USER:$password -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/pypi/hosted" -d @$script_dir/pypi-hosted-k-pip.json
