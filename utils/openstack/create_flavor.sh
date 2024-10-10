#!/bin/bash

# !!! Not work yet
# The script create flavor.
# To create:
#   1) bash create_flavor.sh <qty_cpus>c-<RAM>rm
# Example


#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#Script_dir, current folder
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir/utils

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $IMAGE_SOURCE ]] && IMAGE_SOURCE="https://repo.itkey.com/repository/images"
[[ -z $IMAGE ]] && IMAGE=$1
[[ -z $IMAGE_DIR ]] && IMAGE_DIR="$HOME/images"
# --min-disk $min_disk
[[ -z $MIN_DISK ]] && MIN_DISK=""
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $API_VERSION ]] && API_VERSION="2.74"
[[ -z $TS_YES_NO_INPUT ]] && TS_YES_NO_INPUT=""


error_output () {
#  printf "%s\n" "${yellow}command not executed on $NODES_TYPE nodes${normal}"
  if [ -n "${warning_message}" ]; then
    printf "%s\n" "${yellow}$warning_message${normal}"
    warning_message=""
  fi
  printf "%s\n" "${red}$error_message - error${normal}"
  exit 1
}

yes_no_answer () {
  yes_no_input=""
  while true; do
    read -p "$yes_no_question" yn
    yn=${yn:-"Yes"}
    echo $yn
    case $yn in
        [Yy]* ) yes_no_input="true"; break;;
        [Nn]* ) yes_no_input="false"; break ;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  yes_no_question="<Empty yes\no question>"
}

# COMING SOON ...

if [ -z $IMAGE ]; then
  echo "Try to get images list from repo.itkey.com..."
  echo "Execute curl command:"
  echo "curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json'| jq '.items[]|.name'"
  curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json'| jq '.items[]|.name'
  error_message="You mast define image name as start parameter script"
  error_output
fi

#check_openstack_cli
if [[ $CHECK_OPENSTACK = "true" ]]; then
  if ! bash $utils_dir/check_openstack_cli.sh; then
    echo -e "${red}Failed to check openstack cli - ERROR${normal}"
    exit 1
  fi
fi

if ! bash $utils_dir/check_openrc; then
  exit 1
fi

create_image

