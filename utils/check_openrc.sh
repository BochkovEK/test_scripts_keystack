#!/bin/bash

# The script check openrc file

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#Script_dir, current folder
script_dir=$(dirname $0)

[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc

export OPENRC_PATH=$OPENRC_PATH

check_and_source_openrc_file () {
  echo "Check openrc file..."
  check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
  if [ -z "$check_openrc_file" ]; then
    echo -E "${yellow}openrc file not found in $OPENRC_PATH${normal}"
    echo "Try to get 'openrc' from Vault"
    printf "%s\n" "${red}openrc file not found in $OPENRC_PATH - ERROR!${normal}"
    exit 1
  fi
  echo $OS_PROJECT_NAME
}

check_and_source_openrc_file