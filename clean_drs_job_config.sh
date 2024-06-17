#!/bin/bash

# The script clean all DRS jobs and configs
# To start:
# bash $HOME/test_scripts_keystack/clean_drs_job_config.sh

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"

# Check openrc file
check_openrc_file () {
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && (echo "openrc file not found in $OPENRC_PATH"; exit 1)

    source $OPENRC_PATH
}

check_openrc_file

jobs_list=$(drs jo list -c id|grep "|\s[0-9]\+\s|"|awk '{print $2}')
configs_list=$(drs co list -c id|grep "|\s[0-9]\+\s|"|awk '{print $2}')

for jo in $jobs_list; do
  drs job delete $jo
done

for co in $configs_list; do
  drs config delete $co
done
