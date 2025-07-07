#!/bin/bash

# The script read inventory file and convert it to hosts string
# To start:
# bash ~/test_scripts_keystack/inventory_to_hosts.sh <path_to_inventory_file>
# output "hosts_add_strings"

env_file_name=".inventory_to_hosts_env"
internal_prefix="int"
external_prefix="ext"
region_name="ebochkov"
domain_name="test.domain"
parse_inventory_script="parse_inventory.py"
inventory_file_name="inventory"
output_file_name="hosts_add_strings"
add_strings="# ------ ADD strings ------"

#Color
red=$(tput setaf 1)
#violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

script_dir=$(dirname $0)

#[[ -z $DONT_ASK ]] && DONT_ASK="false"
#[[ -z $EDIT_HOSTS_FILE ]] && EDIT_HOSTS_FILE="false"

#[[ -z $INVENTORY_PATH ]] && INVENTORY_PATH=$script_dir/$inventory_file_name
#[[ -z $OUTPUT_FILE_NAME ]] && OUTPUT_FILE_NAME=$output_file_name
#[[ -z $DOMAIN ]] && DOMAIN=$domain_name
#[[ -z $REGION ]] && REGION=$region_name
#[[ -z $INT_PREF ]] && INT_PREF=$internal_prefix
#[[ -z $EXT_PREF ]] && EXT_PREF=$external_prefix
[[ -z $ADD_STRINGS ]] && ADD_STRINGS=$add_strings
[[ -z $TS_DEBUG ]] && TS_DEBUG=false

while [ -n "$1" ]
do
    case "$1" in
#        -da|dont_ask) DONT_ASK="true"
#          echo "Found the -dont_ask option, with parameter value $DONT_ASK"
#          ;;
#        -edit_hosts) EDIT_HOSTS_FILE="true"
#          echo "Found the -edit_hosts option, with parameter value $EDIT_HOSTS_FILE"
#          ;;
        -d|-domain) DOMAIN=$2
          echo "Found the -domain option, with parameter value $DOMAIN"
          shift
          ;;
        -r|-region) REGION=$2
          echo "Found the -region option, with parameter value $REGION"
          shift
          ;;
        -i|-inventory) INVENTORY_PATH=$2
          echo "Found the -inventory option, with parameter value $INVENTORY_PATH"
          shift
          ;;
        -o|-output_file) OUTPUT_FILE=$2
          echo "Found the -output_file option, with parameter value $OUTPUT_FILE"
          shift
          ;;
        -int_pref) INT_PREF=$2
          echo "Found the -int_pref option, with parameter value $INT_PREF"
          shift
          ;;
        -ext_pref) EXT_PREF=$2
          echo "Found the -ext_pref option, with parameter value $EXT_PREF"
          shift
          ;;
        -v|-debug) TS_DEBUG=true
          echo "Found the -debug option, with parameter value true"
          ;;
        --help) echo -E "
        The script parse inventory file to create $OUTPUT_FILE file like 'hosts' or add strings to hosts
        'inventory' file like this:
          kolla_internal_address=10.224.138.67
          external_floating=10.224.138.68
          [add_vm]
          qa-stable-ubuntu-add_vm-01 ansible_host=10.224.138.82
          [compute]
          qa-stable-ubuntu-comp-01 ansible_host=10.224.138.86
          qa-stable-ubuntu-comp-02 ansible_host=10.224.138.74
          [control]
        'hosts' file or strings in file hosts like this:
          10.224.130.3 int.ebochkov.test.domain backend.int.ebochkov.test.domin
          10.224.130.4 ext.ebochkov.test.domain backend.ext.ebochkov.test.domin

          10.224.130.9 ebochkov-keystack-lcm-01 lcm-01 nexus.test.domain lcm-nexus.test.domain netbox.test.domain gitlab.test.domain vault.test.domain

          10.224.130.7 ebochkov-keystack-add_vm-01 add_vm-01
          10.224.130.13 ebochkov-keystack-comp-01 comp-01
          10.224.130.17 ebochkov-keystack-comp-02 comp-02

        -edit_hosts       without parameters, add strings from inventory to /etc/hosts
        -o, -output_file  <output_file_name_in_test_scripts_keystack_folder> default: $output_file_name
        -d, -domain       <domain_name> example: test.domain default: $domain_name
        -r, -region       <region_name> example: ebochkov default: $region_name
        -i, -inventory    <path_to_inventory_file>  example ./inventory default: $INVENTORY_PATH
        -ext_pref         <external_prefix_for_internal_FQDN> example 'ext'
        -int_pref         <internal_prefix_for_internal_FQDN> example 'int'
        "
          exit 0
          break ;;
	      --) shift
          break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

#if [ -z "$INVENTORY_PATH" ]; then
#  if [ -z "$1" ]; then
#    echo -e "${red}The path to the inventory file path must be passed as an argument or by '-i' key - ERROR${normal}"
#    exit 1
#  fi
#else
#  cat $INVENTORY_PATH
#  if [ ! -f "$INVENTORY_PATH" ]; then
##    echo $INVENTORY_PATH
#    echo -e "${yellow}Inventory file $INVENTORY_PATH not found - WARNING${normal}"
#    echo -e "Create it or specify -i key, or environment var 'INVENTORY_PATH' ${normal}"
#    echo -e "${red}The script cannot be executed - ERROR${normal}"
#    exit 1
#  fi
#fi

# Function to check and set variables
check_and_set_variables() {
    # Check if environment variables exist
    if [[ -z "${INVENTORY_PATH}" ||
          -z "${OUTPUT_FILE_NAME}" ||
          -z "${DOMAIN}" ||
          -z "${REGION}" ||
          -z "${INT_PREF}" ||
          -z "${EXT_PREF}"
        ]]; then

        # If variables are not set, check for $env_file_name file
        if [[ -f "${script_dir}/$env_file_name" ]]; then
            # Load variables from file
            source "${script_dir}/${env_file_name}"
        fi
        # Prompt user for input
        echo "Required environment variables are not set."

        while [[ -z "${INVENTORY_PATH}" ]]; do
          read -rp "Enter inventory file path [$script_dir/$inventory_file_name]: " INVENTORY_PATH
          INVENTORY_PATH=${INVENTORY_PATH:-"$script_dir/$inventory_file_name"}
        done

        while [[ -z "${OUTPUT_FILE_PATH}" ]]; do
          read -rp "Enter output file path [$script_dir/$output_file_name]: " OUTPUT_FILE_PATH
          OUTPUT_FILE_PATH=${OUTPUT_FILE_PATH:-"$script_dir/$output_file_name"}
        done

        while [[ -z "${DOMAIN}" ]]; do
          read -rp "Enter domain [$domain_name]: " DOMAIN
          DOMAIN=${DOMAIN:-"$domain_name"}
        done

        while [[ -z "${REGION}" ]]; do
          read -rp "Enter region name [$region_name]: " REGION
          REGION=${REGION:-"$region_name"}
        done

        while [[ -z "${INT_PREF}" ]]; do
          read -rp "Enter internal VIP prefix [$internal_prefix]: " INT_PREF
          INT_PREF=${INT_PREF:-"$internal_prefix"}
        done

         while [[ -z "${EXT_PREF}" ]]; do
          read -rp "Enter external VIP prefix [$external_prefix]: " EXT_PREF
          EXT_PREF=${EXT_PREF:-"$external_prefix"}
        done

        # Save variables to file
        echo > "${script_dir}/$env_file_name"
        {
          echo "export INVENTORY_PATH=\"${INVENTORY_PATH}\"";
          echo "export OUTPUT_FILE_PATH=\"${OUTPUT_FILE_PATH}\"";
          echo "export DOMAIN=\"${DOMAIN}\"";
          echo "export REGION=\"${REGION}\"";
          echo "export INT_PREF=\"${INT_PREF}\"";
          echo "export EXT_PREF=\"${EXT_PREF}\"";
        } >> "${script_dir}/$env_file_name"
    fi

    if [ "$TS_DEBUG" = true ]; then
      echo "
  [DEBUG]:
    OUTPUT_FILE: $OUTPUT_FILE_PATH
    DOMAIN: $DOMAIN
    REGION: $REGION
    INT_PREF: $INT_PREF
    EXT_PREF: $EXT_PREF
      "
    read -p "Press enter to continue: "
    fi

    # Verify that variables are now set
    if [[ -z "${INVENTORY_PATH}" ||
          -z "${OUTPUT_FILE_NAME}" ||
          -z "${DOMAIN}" ||
          -z "${REGION}" ||
          -z "${INT_PREF}" ||
          -z "${EXT_PREF}"
        ]]; then
        echo -e "${red}Error: Required variables are not set - ERROR${normal}"
        exit 1
    fi
}

python_script_execute () {
  echo "Start parse $INVENTORY_PATH to hosts strings"
  export OUTPUT_FILE_PATH=$OUTPUT_FILE_PATH
  export DOMAIN=$DOMAIN
  export REGION=$REGION
  export INT_PREF=$INT_PREF
  export EXT_PREF=$EXT_PREF

  python3 $script_dir/$parse_inventory_script $INVENTORY_PATH
}

add_to_hosts () {
  add_strings_already_exists=$(cat /etc/hosts | grep "$ADD_STRINGS")
  if [ "$TS_DEBUG" = true ]; then
    echo "
  [DEBUG]:
    add_strings_already_exists: $add_strings_already_exists
    \$script_dir/\$OUTPUT_FILE_NAME: $script_dir/$OUTPUT_FILE_NAME
  "
    read -p "Press enter to continue: "
  fi
  if [ -z "$add_strings_already_exists" ]; then
    echo $ADD_STRINGS >> /etc/hosts
    cat $script_dir/$OUTPUT_FILE_NAME >> /etc/hosts
  fi
}

check_and_set_variables
python_script_execute
add_to_hosts