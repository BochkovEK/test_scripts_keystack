#!/bin/bash

# The script create image.
# To create:
#   1) get list of images from repo.itkey.com images repo
#      curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json'| jq '.items[]|.name'
#   2) bash create_image.sh <image name from repo.itkey.com 'images' repo>
# OR
#    1) export IMAGE_SOURCE="https://cloud-images.ubuntu.com/releases/focal/release/"
#    2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh ubuntu-20.04-server-cloudimg-amd64.img
#     or
#    1) http://cloud-images-archive.ubuntu.com/releases/noble/release-20240523.1/
#    2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh ubuntu-24.04-server-cloudimg-amd64.img
#     or
#    2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh cirros-0.6.2-x86_64-disk.img

#images_list=(
##  "ubuntu-20.04-server-cloudimg-amd64.img"
##  "jammy-server-cloudimg-amd64.img"
#  "cirros-0.6.2-x86_64-disk.img"
##  "ubuntu-20.04-server-cloudimg-amd64.img"
#  )
#public_images_list=(
##  "ubuntu-20.04-server-cloudimg-amd64.img"
#  "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img"
#  )


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
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
#install_wget_script="install_wget.sh"
yes_no_answer_script="yes_no_answer.sh"
install_package_script="install_package.sh"

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $IMAGE_SOURCE ]] && IMAGE_SOURCE="https://repo.itkey.com/repository/images/"
[[ -z $IMAGE ]] && IMAGE=$1
[[ -z $IMAGE_DIR ]] && IMAGE_DIR="$HOME/images"
# --min-disk $min_disk
[[ -z $MIN_DISK ]] && MIN_DISK=""
#[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $API_VERSION ]] && API_VERSION="2.74"
#[[ -z $TS_YES_NO_INPUT ]] && TS_YES_NO_INPUT=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"


error_output () {
#  printf "%s\n" "${yellow}command not executed on $NODES_TYPE nodes${normal}"
  if [ -n "${warning_message}" ]; then
    printf "%s\n" "${yellow}$warning_message${normal}"
    warning_message=""
  fi
  printf "%s\n" "${red}$error_message - ERROR${normal}"
  exit 1
}

#yes_no_answer () {
#  yes_no_input=""
#  while true; do
#    read -p "$yes_no_question" yn
#    yn=${yn:-"Yes"}
#    echo $yn
#    case $yn in
#        [Yy]* ) yes_no_input="true"; break;;
#        [Nn]* ) yes_no_input="false"; break ;;
#        * ) echo "Please answer yes or no.";;
#    esac
#  done
#  yes_no_question="<Empty yes\no question>"
#}

check_and_source_openrc_file () {
#  echo "check openrc"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
#  if bash $utils_dir/$check_openrc_script 2>&1; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    exit 1
  fi
}

check_openstack_cli () {
#  echo "check"
  if [[ $CHECK_OPENSTACK = "true" ]]; then
    if ! bash $utils_dir/$check_openstack_cli_script &> /dev/null; then
      echo -e "${red}Failed to check openstack cli - ERROR${normal}"
      exit 1
    fi
  fi
}

# Create image
create_image () {
  echo "Check for exist image: \"$IMAGE\""
   #in project \"$PROJECT\""
  image_exists_in_openstack=$(openstack image list| grep -m 1 "$IMAGE"| awk '{print $2}')
  [ "$TS_DEBUG" = true ] && echo -e "image_exists_in_openstack: $image_exists_in_openstack"
  if [ -n "$image_exists_in_openstack" ]; then
    echo -e "${green}Image \"$IMAGE\" already exist - ok!${normal}"
    exit 0
  else
    echo -e "${yellow}Image \"$IMAGE\" not found${normal}"
     #in project \"$PROJECT\"${normal}"
    if [ $DONT_ASK = "true" ]; then
      yes_no_input="true"
    else
      export TS_YES_NO_QUESTION="Do you want to try to create $IMAGE [Yes]:"
#       in project $PROJECT [Yes]:"
      yes_no_input=$(bash $utils_dir/$yes_no_answer_script)
    fi
    if [ ! "$yes_no_input" = "true" ]; then
      echo -e "${yellow}Image $IMAGE does not created${normal}"
      exit 0
    else
      if [ -f $script_dir/"$IMAGE" ]; then
        mkdir -p $IMAGE_DIR
        cp $script_dir/"$IMAGE" $IMAGE_DIR/$IMAGE
      fi
      if [ -f $IMAGE_DIR/"$IMAGE" ]; then
        echo -e "${green}File $IMAGE exist - ok!${normal}"
      else
        echo -e "${yellow}File $IMAGE does not exist${normal}"
        if [ -z "$IMAGE_SOURCE" ]; then
          warning_message="Global variable \$IMAGE_SOURCE does not define"
          error_message="Image $IMAGE does not created"
          error_output
        else
          if [ $DONT_ASK = "true" ]; then
            yes_no_input="true"
          else
            export TS_YES_NO_QUESTION="Do you want to try to download $IMAGE from source: $IMAGE_SOURCE [Yes]:"
            yes_no_input=$(bash $utils_dir/$yes_no_answer_script)
          fi
          if [ ! "$yes_no_input" = "true" ]; then
            error_message="Image $IMAGE does not created"
            error_output
          else
            if ! bash $utils_dir/$install_package_script wget; then
              error_message="Image $IMAGE does not created"
              error_output
            else
              wget $IMAGE_SOURCE$IMAGE -P $IMAGE_DIR/
            fi
          fi
        fi
      fi
      echo "Creating image \"$IMAGE\""
#       in project \"$PROJECT\"..."
      openstack image create "$IMAGE" \
        --disk-format qcow2 \
        --container-format bare \
        --public \
        $MIN_DISK --file $IMAGE_DIR/$IMAGE
    fi
  fi
  image_exists_in_openstack=$(openstack image list| grep -m 1 "$IMAGE"| awk '{print $2}')
  echo "image_exists_in_openstack: $image_exists_in_openstack"
  if [ -n "${image_exists_in_openstack}" ]; then
    echo -E "${green}$IMAGE created in $PROJECT - ok!${normal}"
  else
    error_message="Image $IMAGE does not created"
    error_output
  fi
}


echo "$script_name script started..."

if [ -z $IMAGE ]; then
  echo "Try to get images list from repo.itkey.com..."
  echo "Execute curl command:"
  echo "curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json'| jq '.items[]|.name'"
  curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json'| jq '.items[]|.name'
  error_message="You must define image name as start parameter script"
  error_output
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

check_openstack_cli
check_and_source_openrc_file
create_image

