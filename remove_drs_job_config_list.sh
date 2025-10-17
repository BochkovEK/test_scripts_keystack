#!/bin/bash

# Script to remove all DRS jobs and configurations
# Usage: bash remove_drs_job_config.sh

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"

# Function to validate and source openrc file
check_openrc_file() {
    [[ ! -f "$OPENRC_PATH" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
    source "$OPENRC_PATH"
}

# Function to get list of DRS jobs
get_drs_jobs() {
    drs job list -c id | grep -E "\|\s+[0-9]+\s+\|" | awk '{print $2}'
}

# Function to get list of DRS configs
get_drs_configs() {
    drs config list -c id | grep -E "\|\s+[0-9]+\s+\|" | awk '{print $2}'
}

# Function to delete DRS jobs
delete_jobs() {
    local jobs_list="$1"
    for job in $jobs_list; do
        echo "Deleting job: $job"
        drs job delete "$job"
    done
}

# Function to delete DRS configs
delete_configs() {
    local configs_list="$1"
    for config in $configs_list; do
        echo "Deleting config: $config"
        drs config delete "$config"
    done
}

# Function to display current DRS status
show_status() {
    echo "Current DRS jobs:"
    drs job list
    echo -e "\nCurrent DRS configs:"
    drs config list
}

# Main execution function
main() {
    check_openrc_file

    local jobs_list=$(get_drs_jobs)
    local configs_list=$(get_drs_configs)

    echo "DRS jobs to delete: $jobs_list"
    echo "DRS configs to delete: $configs_list"

    if [[ -z "$jobs_list" && -z "$configs_list" ]]; then
        echo "No DRS jobs or configs found to delete."
        exit 0
    fi

    echo -e "\nDelete all DRS jobs and configs?"
    read -p "Press Enter to continue or Ctrl+C to cancel: "

    delete_jobs "$jobs_list"
    delete_configs "$configs_list"

    echo -e "\nFinal status:"
    show_status
}

main "$@"