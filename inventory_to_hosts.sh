#!/bin/bash

# The script read inventory file and convert it to hosts string
# To start:
# bash ~/test_scripts_keystack/inventory_to_hosts.sh <path_to_inventory_file>
# output "hosts_add_strings"

parse_inventory_script="parse_inventory.py"
inventory_file_name="dns_ip_mapping.txt"
output_file_name="hosts_add_strings"

#Color
red=$(tput setaf 1)
#violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

script_dir=$(dirname $0)

[[ -z $DOMAIN ]] && DOMAIN="test.domain"
[[ -z $REGION ]] && REGION="ebochkov"
[[ -z $INVENTORY_PATH ]] && INVENTORY_PATH=$script_dir/$inventory_file_name
[[ -z $OUTPUT_FILE ]] && OUTPUT_FILE=$output_file_name

while [ -n "$1" ]
do
    case "$1" in
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
        --help) echo -E "
        The script parse inventory file to create $OUTPUT_FILE file like 'hosts'
        'inventory' file like this:
          kolla_internal_address=10.224.138.67
          external_floating=10.224.138.68
          [add_vm]
          qa-stable-ubuntu-add_vm-01 ansible_host=10.224.138.82
          [compute]
          qa-stable-ubuntu-comp-01 ansible_host=10.224.138.86
          qa-stable-ubuntu-comp-02 ansible_host=10.224.138.74
          [control]
        'hosts' file like this:
          10.224.130.3 int.ebochkov.test.domain backend.int.ebochkov.test.domin
          10.224.130.4 ext.ebochkov.test.domain backend.ext.ebochkov.test.domin

          10.224.130.9 ebochkov-keystack-lcm-01 lcm-01 nexus.test.domain lcm-nexus.test.domain netbox.test.domain gitlab.test.domain vault.test.domain

          10.224.130.7 ebochkov-keystack-add_vm-01 add_vm-01
          10.224.130.13 ebochkov-keystack-comp-01 comp-01
          10.224.130.17 ebochkov-keystack-comp-02 comp-02

        -d, -domain       <domain_name> example: test.domain
        -r, -region       <region_name> example: ebochkov
        -i, -inventory    <path_to_inventory_file>  example ./inventory
        -o, -output_file  <output_file_name_in_test_scripts_keystack_folder>
        "
          exit 0
          break ;;
	      --) shift
          break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

if [ -z "$INVENTORY_PATH" ]; then
  if [ -z "$1" ]; then
    echo -e "${red}The path to the inventory file must be passed as an argument - ERROR${normal}"
    exit 1
  fi
else
  if [ ! -f $INVENTORY_PATH ]; then
    echo -e "${yellow}Inventory file $INVENTORY_PATH not found - WARNING${normal}"
    echo -e "Create it or specify -i key, or environment var $INVENTORY_PATH ${normal}"
    echo -e "${red}The script cannot be executed - ERROR${normal}"
    exit 1
  fi
fi

python_script_execute () {
  echo "Start parse $INVENTORY_PATH to hosts strings"
  export DOMAIN=$DOMAIN
  export REGION=$REGION
  export OUTPUT_FILE=$OUTPUT_FILE
  python3 $script_dir/$parse_inventory_script $INVENTORY_PATH
}

python_script_execute