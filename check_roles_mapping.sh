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
violet=$(tput setaf 5)
cyan=$(tput setaf 6)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
utils_dir=$script_dir/utils
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
yes_no_answer_script="yes_no_answer.sh"

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $DOMAIN ]] && DOMAIN="test_domain"
[[ -z $PROJECT ]] && PROJECT="test_project"
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"
[[ -z $ROLE_MAPPING_FILE ]] && ROLE_MAPPING_FILE=""


# Define parameters
define_parameters () {
  [ "$DEBUG" = true ] && echo "[DEBUG]: \"\$1\": $1"
  [ "$count" = 1 ] && [[ -n $1 ]] && { ROLE_MAPPING_FILE=$1; echo "ROLE_MAPPING_FILE: $ROLE_MAPPING_FILE"; }
#  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
    The script check roles, users, groups
    To start: bash check_openstack_roles.sh <path_to_role_mapping_file>
    Example <path_to_role_mapping_file>:
    <group_name> <role> <user_name1> <user_name2> ... <user_name_n>
    cat ./role_mapping_example.txt
    preevostack_infra_admin   admin   infra_admin
    preevostack_member        member  member1      member2 member3
"
      exit 0
      break ;;
	  --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done


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

create_test_project () {
  echo "Check for exist project: \"$PROJECT\"..."
  PROJ_ID=$(openstack project list| grep -E -m 1 "\s$PROJECT\s"| awk '{print $2}')
  if [ -z "$PROJ_ID" ]; then
    printf "%s\n" "${yellow}Project \"$PROJECT\" does not exist${normal}"
    if [ ! $DONT_ASK = "true" ]; then
      export TS_YES_NO_QUESTION="Do you want to try to create $PROJECT [Yes]:"
      yes_no_input=$(bash $utils_dir/$yes_no_answer_script)
    else
      yes_no_input="true"
    fi
    if [ "$yes_no_input" = "true" ]; then
      PROJ_ID=$(openstack project create $PROJECT --domain $DOMAIN|grep -E "\sid\s"| awk '{print $4}')
      openstack project show $PROJ_ID
    fi
  fi
}

check_users_in_group () {
  echo "Check users in group..."
  for map in "${ROLE_MAPPING[@]}"; do
    i=1
    group_name=""
#    role_name=""
    user_id=""
    group_id=""
    for word in $map; do
      user_id=""
      if (( $i == 1 )); then
        group_name=$word
        echo -e "${violet}group_name: $group_name${normal}"
        i=$((i + 1))
      elif (( $i == 2 )); then
#        role_name=$word
#        echo role_name: $role_name
        i=$((i + 1))
      elif [ $i -gt 2 ]; then
        user_name=$word
        echo -e "${cyan}user_name: $user_name${normal}"
        user_id=$(openstack user list --domain $DOMAIN|grep -E "\s$word\s"|awk '{print $2}')
        group_id=$(openstack group list --domain $DOMAIN|grep -E "\s$group_name\s"| awk '{print $2}')
        openstack group contains user $group_id $user_id
        i=$((i + 1))
      fi
    done
  done
}

add_role_for_groups () {
  echo "Add role for groups in project: $PROJECT; domain: $DOMAIN..."
  echo "PROJ_ID: $PROJ_ID"
  for map in "${ROLE_MAPPING[@]}"; do
    i=1
    group_name=""
    role_name=""
    group_id=""
    for word in $map; do
      if (( $i == 1 )); then
        group_name=$word
        echo -e "${violet}group_name: $group_name${normal}"
        i=$((i + 1))
      elif (( $i == 2 )); then
        role_name=$word
        echo -e "${blue}role_name: $role_name${normal}"
        group_id=$(openstack group list --domain $DOMAIN|grep -E "\s$group_name\s"| awk '{print $2}')
        openstack role add $role_name --group $group_id --project $PROJ_ID
        echo "Check role: $role_name for group: $group_name in project: $PROJECT..."
        openstack role assignment list --group $group_id --project $PROJ_ID --names
        break
      fi
    done
  done
}

#check_group_roles_in_project () {
#  echo "start check_group_roles_in_project function"
#}

# check start parameter
if [ -z "${1}" ]; then
  if [ -z "$ROLE_MAPPING_FILE" ]; then
    error_message="You mast define <path_to_role_mapping_file> as start parameter script"
    error_output
  fi
else
  ROLE_MAPPING_FILE=$1
fi

#while IFS= read -r line; do echo ">>$line<<"; done < $ROLE_MAPPING_FILE
while IFS= read -r line; do ROLE_MAPPING+=("$line"); done < $ROLE_MAPPING_FILE

if [ "$TS_DEBUG" = true ]; then
  echo -e "
  [TS_DEBUG]
    ROLE_MAPPING_FILE: $ROLE_MAPPING_FILE
    ROLE_MAPPING:
"
  for map in "${ROLE_MAPPING[@]}"; do
    echo $map
  done
fi

check_openstack_cli
check_and_source_openrc_file
create_test_project
check_users_in_group
if [ -n "$PROJ_ID" ]; then
  add_role_for_groups
#  check_group_roles_in_project
fi
