#!/bin/bash

# The script create image.
# To create:
#   1) get list of images from repo.itkey.com images repo
#      curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json'| jq '.items[]|.name'
#   2) bash create_image.sh <image name from repo.itkey.com 'images' repo>


#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#Script_dir, current folder
script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $IMAGE_SOURCE ]] && IMAGE_SOURCE="https://repo.itkey.com/repository/images"
[[ -z $IMAGE ]] && IMAGE=$1
[[ -z $IMAGE_DIR ]] && IMAGE_DIR="$HOME/images"
# --min-disk $min_disk
[[ -z $MIN_DISK ]] && MIN_DISK=""
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $API_VERSION ]] && API_VERSION="2.74"
#[[ -z $TS_YES_NO_INPUT ]] && TS_YES_NO_INPUT=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"


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

# Create image
create_image () {
  image_exists_in_openstack=$(openstack image list| grep -m 1 "$IMAGE"| awk '{print $2}')
  echo "image_exists_in_openstack: $image_exists_in_openstack"
  if [ -n "${image_exists_in_openstack}" ]; then
    if [ ! $DONT_ASK = "true" ]; then
      export TS_YES_NO_QUESTION="Do you want to try to create $IMAGE [Yes]:"
      yes_no_input=$(bash $utils_dir/yes_no_answer.sh)
    else
      yes_no_input="true"
    fi
  else
    yes_no_input="true"
  fi
  if [ "$yes_no_input" = "true" ]; then
    bash $utils_dir/install_wget.sh
    echo "Creating image \"$IMAGE\" in project \"$PROJECT\"..."
    [ -f $script_dir/"$IMAGE" ] && echo "File $IMAGE_DIR/$IMAGE exist." \
    || { echo "File $IMAGE_DIR/$IMAGE does not exist. Try to download it..."; \
    wget $IMAGE_SOURCE/$IMAGE -P $IMAGE_DIR/; }

    openstack image create "$IMAGE" \
      --disk-format qcow2 \
      --container-format bare \
      --public \
      $MIN_DISK --file $IMAGE_DIR/$IMAGE
  else
    echo -E "${yellow}$IMAGE not created${normal}"
    exit 0
  fi
}


echo "$script_name script started..."

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
#    echo -e "\033[31mFailed to check openstack cli - error\033[0m"
    exit 1
  fi
fi

if ! bash $utils_dir/check_openrc.sh; then
  exit 1
fi

[ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]
  OS_PROJECT_DOMAIN_NAME:   $OS_PROJECT_DOMAIN_NAME
  OS_USER_DOMAIN_NAME:      $OS_USER_DOMAIN_NAME
  OS_PROJECT_NAME:          $OS_PROJECT_NAME
  OS_TENANT_NAME:           $OS_TENANT_NAME
  OS_USERNAME:              $OS_USERNAME
  OS_PASSWORD:              $OS_PASSWORD
  OS_AUTH_URL:              $OS_AUTH_URL
  OS_INTERFACE:             $OS_INTERFACE
  OS_ENDPOINT_TYPE:         $OS_ENDPOINT_TYPE
  OS_IDENTITY_API_VERSION:  $OS_IDENTITY_API_VERSION
  OS_REGION_NAME:           $OS_REGION_NAME
  OS_AUTH_PLUGIN:           $OS_AUTH_PLUGIN
  OS_DRS_ENDPOINT_OVERRIDE: $OS_DRS_ENDPOINT_OVERRIDE
  ---
  PROJECT:                  $PROJECT
  IMAGE:                    $IMAGE
  IMAGE_SOURCE:             $IMAGE_SOURCE
  IMAGE_DIR:                $IMAGE_DIR
"

create_image

