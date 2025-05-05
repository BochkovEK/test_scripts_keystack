#!/bin/bash

# The script create pub_net from LCM or jump host only
# To get pub_net settings:
# export GET_SETTINGS=true
# bash ~/test_scripts_keystack/utils/openstack/create_pub_network.sh

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
yes_no_answer_script="yes_no_answer.sh"

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $API_VERSION ]] && API_VERSION="2.74"
[[ -z $NETWORK ]] && NETWORK="pub_net"
#[[ -z $TS_YES_NO_QUESTION ]] && TS_YES_NO_QUESTION=""
#[[ -z $TS_YES_NO_INPUT ]] && TS_YES_NO_INPUT=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"
[[ -z $GET_SETTINGS ]] && GET_SETTINGS="false"


error_output () {
#  printf "%s\n" "${yellow}command not executed on $NODES_TYPE nodes${normal}"
  if [ -n "${warning_message}" ]; then
    printf "%s\n" "${yellow}$warning_message${normal}"
    warning_message=""
  fi
  printf "%s\n" "${red}$error_message - error${normal}"
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
    if ! bash $utils_dir/$check_openstack_cli_script; then
     #&> /dev/null; then
      echo -e "${red}Failed to check openstack cli - ERROR${normal}"
      exit 1
    fi
  fi
}

# Check network
get_settings () {

  CIDR=$(ip r|grep "dev external proto kernel scope"| awk '{print $1}');
  last_digit=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\.[0-9]+\.[0-9]+\.)|(\/[0-9]+)//g');
  left_side=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\/[0-9]+)//g');
  GATEWAY=$left_side$(expr $last_digit + 1);
#  echo "CIDR: $CIDR, GATEWAY: $GATEWAY"
  if [ -n "$CIDR" ] && [ -n "$GATEWAY" ]; then
    mask_pub_net=$(echo "${CIDR##*/}")
    if [ "$mask_pub_net" = "27" ]; then
      case "$last_digit" in
        0)
          start_pub_net_ip="${left_side}10"
          end_pub_net_ip="${left_side}30"
          ;;
        32)
          start_pub_net_ip="${left_side}40"
          end_pub_net_ip="${left_side}62"
          ;;
        64)
          start_pub_net_ip="${left_side}70"
          end_pub_net_ip="${left_side}94"
          ;;
        96)
          start_pub_net_ip="${left_side}100"
          end_pub_net_ip="${left_side}126"
          ;;
        128)
          start_pub_net_ip="${left_side}140"
          end_pub_net_ip="${left_side}158"
          ;;
        160)
          start_pub_net_ip="${left_side}170"
          end_pub_net_ip="${left_side}190"
          ;;
        192)
          start_pub_net_ip="${left_side}200"
          end_pub_net_ip="${left_side}222"
          ;;
        224)
          start_pub_net_ip="${left_side}230"
          end_pub_net_ip="${left_side}254"
          ;;
      esac
    else
      warning_message="The script can only create a 'pub_net' with '27' mask"
      error_message="Network $NETWORK does not created"
      error_output
    fi
  else
    warning_message="Script can't define CIDR or GATEWAY on this node. Try use the script on lcm or jump node"
    error_message="Network $NETWORK does not created"
    error_output
  fi
}

create_pub_network () {
  echo "Check for exist network: \"$NETWORK\""
  NETWORK_NAME_EXIST=$(openstack network list| grep "$NETWORK"| awk '{print $2}')
  if [ -z "$NETWORK_NAME_EXIST" ]; then
    echo -e "${yellow}Network \"$NETWORK\" not found in project \"$PROJECT\"${normal}"
    if [ "$NETWORK" = "pub_net" ]; then
      if [ ! $DONT_ASK = "true" ]; then
        export TS_YES_NO_QUESTION="Do you want to try to create $NETWORK [Yes]:"
        yes_no_input=$(bash $utils_dir/$yes_no_answer_script)
      else
        yes_no_input="true"
      fi
      if [ "$yes_no_input" = "true" ]; then
        openstack network create \
          --external \
          --share \
          --provider-network-type flat \
          --provider-physical-network physnet1 \
          $NETWORK
        openstack subnet create \
          --subnet-range $CIDR \
          --network pub_net \
          --dhcp \
          --gateway $GATEWAY \
          --allocation-pool start=$start_pub_net_ip,end=$end_pub_net_ip \
          $NETWORK
      else
        error_message="Network $NETWORK does not created"
        error_output
      fi
    else
      warning_message="The script can only create a 'pub_net' network"
      error_message="Network $NETWORK does not created"
      error_output
    fi
  else
    echo -e "${green}Network \"$NETWORK\" already exist in project \"$PROJECT\"${normal}"
  fi
}

echo "$script_name script started..."

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
  NETWORK:                  $NETWORK
  GET_SETTINGS:             $GET_SETTINGS
"

get_settings
if [ "$GET_SETTINGS" = "true" ]; then
  echo "
    CIDR:               $CIDR
    GATEWAY:            $GATEWAY
    start_pub_net_ip:   $start_pub_net_ip
    end_pub_net_ip:     $end_pub_net_ip
  "
  exit 0
fi
check_openstack_cli
check_and_source_openrc_file
create_pub_network