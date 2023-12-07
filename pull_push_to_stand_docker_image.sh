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

source $SETTINGS && \
docker pull ${REPO_ITKEY}/${REPO_FOLDER}/${tag} && \
docker tag ${REPO_ITKEY}/${REPO_FOLDER}/${tag} nexus.${DOMAIN}/${REPO_FOLDER}/${tag} && \
docker push nexus.${DOMAIN}/${REPO_FOLDER}/${tag}
