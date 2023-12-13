#!/bin/bash

#the script pull from repo itkey, tag, push to nexus stand
#the script needs credentials for repo itkey (vi ~/.docker/config.json)
#config.json:
#{
#  "auths": {
#          "nexus.demo.local": {
#                  "auth": "foo"
#           },
#          "repo.itkey.com:8443": {
#                  "auth": "bar"
#    }
#  }
#}
#Stsrt example bash pull_push_to_stand_docker_image.sh drs:ks-2023.2-rc7

INSTALLER_HOME=/installer
SETTINGS=$INSTALLER_HOME/config/settings
REPO_ITKEY=repo.itkey.com:8443
REPO_FOLDER=project_k

[[ -z "${1}" ]] && { echo -e "Required to specify the tag as a launch parameter\nexample: bash kpull_push_to_stand_docker_image.sh kolla-ansible:ks2023.2.1-rc1"; exit 1; }
tag=$1
echo "Source tag: $tag"
tag_target=$tag
[[ -n "${2}" ]] && { echo -e "Second parameter found. tag_target=$2"; tag_target=$2; }

echo "Source settings file $SETTINGS..."
source $SETTINGS && \
echo "Pulling ${REPO_ITKEY}/${REPO_FOLDER}/${tag}..." && \
docker pull ${REPO_ITKEY}/${REPO_FOLDER}/${tag}
echo "Tagging ${REPO_ITKEY}/${REPO_FOLDER}/${tag} to nexus.${DOMAIN}/${REPO_FOLDER}/${tag_target}..." && \
docker tag ${REPO_ITKEY}/${REPO_FOLDER}/${tag} nexus.${DOMAIN}/${REPO_FOLDER}/${tag_target} && \
echo "Pushing nexus.${DOMAIN}/${REPO_FOLDER}/${tag_target}..." && \
docker push nexus.${DOMAIN}/${REPO_FOLDER}/${tag_target}
