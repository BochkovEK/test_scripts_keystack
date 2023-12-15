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
TAG=""
TAG_TARGET=""

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -s, -source         <source_repo_name: repo.itkey.com:8443>
        -st, -tag_source    <source_tag_name_from_repo: adminui-backend:ks2023.2.1>
        -tt, -tag_target    <target_tag_name_on_stand: adminui-backend:ks2023.2.1>
        -rf, -repo_folder   <repo_folder_name: project_k>
"
      exit 0
      break ;;
	-s|-source) REPO_ITKEY="$2"
      echo "Found the -source <source_repo_name: repo.itkey.com:8443> option, with parameter value: $REPO_REPO_ITKEY"
      shift ;;
  -st|-tag_source) TAG="$2"
      echo "Found the -tag_source <source_tag_name_from_repo: adminui-backend:ks2023.2.1> option, with parameter value: $TAG"
      shift ;;
  -tt|-tag_target) TAG_TARGET="$2"
      echo "Found the -tag_target    <target_tag_name_on_stand: adminui-backend:ks2023.2.1> option, with parameter value: $TAG_TARGET"
      shift ;;
  -rf|-repo_folder) REPO_FOLDER="$2"
      echo "Found the -repo_folder <repo_folder_name: project_k> option, with parameter value: $REPO_FOLDER"
      shift ;;
  *)
    break ;;
    esac
done

# Define parameters
count=1
for param in "$@"; do
  echo "Parameter #$count: $param"
  [ "$count" = 1 ] && [[ -n $param ]] && { TAG=$param; echo "Found the -tag_source <source_tag_name_from_repo: adminui-backend:ks2023.2.1> option, with parameter value: $TAG"; }
  [ "$count" = 1 ] && [[ -n $param ]] && { TAG_TARGET=$param; echo "Found the -tag_target <target_tag_name_from_repo: adminui-backend:ks2023.2.1> option, with parameter value: $TAG_TARGET"; }
  count=$(( $count + 1 ))
done

[ -z "$TAG" ] && { echo -e "Required to specify the tag as a launch parameter\nexample: bash pull_push_to_stand_docker_image.sh kolla-ansible:ks2023.2.1-rc1"; exit 1; }
[ -z "$TAG_TARGET" ] && { TAG_TARGET=$TAG; }

#[[ -z "${1}" ]] && { echo -e "Required to specify the tag as a launch parameter\nexample: bash kpull_push_to_stand_docker_image.sh kolla-ansible:ks2023.2.1-rc1"; exit 1; }
#tag=$1
#echo "Source tag: $tag"
#tag_target=$tag
#[[ -n "${2}" ]] && { echo -e "Second parameter found. tag_target=$2"; tag_target=$2; }

echo "Source settings file $SETTINGS..."
source $SETTINGS

echo -E "
The following actions will be performed:
        Pulling tag: ${REPO_ITKEY}/${REPO_FOLDER}/${TAG}
        Tagging: ${REPO_ITKEY}/${REPO_FOLDER}/${TAG} to nexus.${DOMAIN}/${REPO_FOLDER}/${TAG_TARGET}
        Pushing tag: nexus.${DOMAIN}/${REPO_FOLDER}/${TAG_TARGET}
        "
read -r -p "Press enter to continue"

echo "Pulling ${REPO_ITKEY}/${REPO_FOLDER}/${TAG}..." && \
docker pull ${REPO_ITKEY}/${REPO_FOLDER}/${TAG}
echo "Tagging ${REPO_ITKEY}/${REPO_FOLDER}/${TAG} to nexus.${DOMAIN}/${REPO_FOLDER}/${TAG_TARGET}..." && \
docker tag ${REPO_ITKEY}/${REPO_FOLDER}/${TAG} nexus.${DOMAIN}/${REPO_FOLDER}/${TAG_TARGET} && \
echo "Pushing nexus.${DOMAIN}/${REPO_FOLDER}/${TAG_TARGET}..." && \
docker push nexus.${DOMAIN}/${REPO_FOLDER}/${TAG_TARGET}
