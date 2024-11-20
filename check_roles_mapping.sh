#!/bin/bash

# The script check roles, users, groups
# To start: bash check_openstack_roles.sh <path_to_role_mapping_file>
# Example <path_to_role_mapping_file>:
# <group_name> <role> <user_name1> <user_name2> ... <user_name_n>
# cat ./path_to_role_mapping_file.txt
# preevostack_infra_admin admin infra_admin
# preevostack_member member member1 member2 member3

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
utils_dir=$script_dir/utils
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
yes_no_answer_script="yes_no_answer.sh"

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $PROJECT ]] && PROJECT="test_project"
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"
[[ -z $ROLE_MAPPING_FILE ]] && ROLE_MAPPING_FILE=""


error_output () {
#  printf "%s\n" "${yellow}command not executed on $NODES_TYPE nodes${normal}"
  if [ -n "${warning_message}" ]; then
    printf "%s\n" "${yellow}$warning_message${normal}"
    warning_message=""
  fi
  printf "%s\n" "${red}$error_message - ERROR${normal}"
  exit 1
}

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

# check start parameter
if [ -z "${1}" ]; then
  #] && echo -e "

  if [ -z $ROLE_MAPPING_FILE ]; then
    error_message="You mast define <path_to_role_mapping_file> as start parameter script"
    error_output
  fi
else
  ROLE_MAPPING_FILE=$1
fi

#while IFS= read -r line; do echo ">>$line<<"; done < $ROLE_MAPPING_FILE
while IFS= read -r line; do ROLE_MAPPING+=("$line"); done < $ROLE_MAPPING_FILE

for map in "${ROLE_MAPPING[@]}"; do
  echo $map
done