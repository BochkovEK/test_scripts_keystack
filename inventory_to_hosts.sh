#!/bin/bash

# The script read inventory file and convert it to hosts string
# To start:
# bash ~/test_scripts_keystack/inventory_to_hosts.sh <path_to_inventory_file>

parse_inventory_script="parse_inventory.py"

#Color
red=$(tput setaf 1)
#violet=$(tput setaf 5)
normal=$(tput sgr0)


script_dir=$(dirname $0)

if [ -z "$1" ]
  then
    echo -e "${red}The path to the inventory file must be passed as an argument - ERROR${normal}"
    exit 1
fi

python_script_execute () {
  echo "Start parse $1 to hosts strings"
  python3 $script_dir/$parse_inventory_script $1
}

python_script_execute $1