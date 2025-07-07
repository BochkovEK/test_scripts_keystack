#!/bin/bash

# To gen job_key.pub
#ssh-keygen -y -f job_key > job_key.pub

ssh_sudo_user="kolla"
ca_crt_path="$HOME/installer/mutiple-node/certs/ca.crt"
env_file_name=".deploy_certs_env"


# Determine the directory where the script is located
script_dir=$(dirname "$(readlink -f "$0")")

# Function to check and set variables
check_and_set_variables() {
    # Check if environment variables exist
    if [[ -z "${NEXUS_FQDN}" ||
          -z "${HOSTS_LIST}" ||
          -z "${SSH_SUDO_USER}" ||
          -z "${CA_CRT_PATH}"
       ]]; then
        # If variables are not set, check for $env_file_name file
        if [[ -f "${script_dir}/$env_file_name" ]]; then
            # Load variables from file
            source "${script_dir}/${env_file_name}"
        fi
        # Prompt user for input
        echo "Required environment variables are not set."

        while [[ -z "${SSH_SUDO_USER}" ]]; do
          read -rp "Enter ssh sudo user name [$ssh_sudo_user]: " SSH_SUDO_USER
          SSH_SUDO_USER=${SSH_SUDO_USER:-"$ssh_sudo_user"}
        done

        while [[ -z "${NEXUS_FQDN}" ]]; do
          read -p "Enter Nexus service FQDN: " NEXUS_FQDN
        done

        while [[ -z "${HOSTS_LIST}" ]]; do
          HOSTS_LIST=$(cat /etc/hosts | grep -E "ctrl|comp|net-" | awk '{print $1}')
          if [[ -z "${HOSTS_LIST}" ]]; then
            read -p "Enter list of hosts (space-separated): " HOSTS_LIST
          fi
        done

        while [[ -z "${CA_CRT_PATH}" ]]; do
          read -rp "Enter CA cert path [$ca_crt_path]: " CA_CRT_PATH
          CA_CRT_PATH=${CA_CRT_PATH:-"$ca_crt_path"}
        done

        # Save variables to file
        echo "export SSH_SUDO_USER=\"${SSH_SUDO_USER}\"" > "${script_dir}/$env_file_name"
        {
          echo "export NEXUS_FQDN=\"${NEXUS_FQDN}\"";
          echo "export HOSTS_LIST=\"${HOSTS_LIST}\"";
          echo "export CA_CRT_PATH=\"${CA_CRT_PATH}\"";
        } >> "${script_dir}/$env_file_name"
    fi

    # Verify that variables are now set
    if [[ -z "${NEXUS_FQDN}" || -z "${HOSTS_LIST}" || -z "${SSH_SUDO_USER}" ]]; then
        echo "Error: Required variables NEXUS_FQDN and HOSTS_LIST are not set."
        exit 1
    fi
}

# SED init configuration
sed_init_config () {
  #source /installer/config/settings
  echo "Sed repos templates..."
  sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" "${script_dir}/pip.conf"
  sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" "${script_dir}/sberlinux-9.repo"
  echo "cat pip.conf:"
  cat "${script_dir}/pip.conf"
  echo "cat sberlinux-9.repo:"
  cat "${script_dir}/sberlinux-9.repo"
}

# Functions for each mode
setup_certs() {
  echo "Configuring certificates..."
  for host in $srv; do
    sudo sh -c "cat $ca_crt_path" |ssh $SSH_SUDO_USER@$host "sudo tee /etc/pki/ca-trust/source/anchors/ca.crt > /dev/null"
  done
  for host in $srv;do ssh $SSH_SUDO_USER@$host "sudo sh -c 'update-ca-trust'";done
}

setup_repo() {
  echo "Configuring repository..."
  sed_init_config
  for host in $srv; do
    cat $script_dir/sberlinux-9.repo | ssh $SSH_SUDO_USER@$host "sudo tee /etc/yum.repos.d/sberlinux.repo > /dev/null"
  done
  for host in $srv;do ssh $SSH_SUDO_USER@$host "sudo sh -c 'yum -y update'";done
}

setup_pip_repo() {
  echo "Configuring PIP repository..."
  for host in $srv; do
    cat $script_dir/pip.conf | ssh $SSH_SUDO_USER@$host "sudo tee /etc/pip.conf > /dev/null"
  done
}

setup_public_key() {
  echo "Configuring gitlab job_key.pub..."
  if [[ -f "${script_dir}/job_key.pub" ]]; then
    for host in $srv; do
      cat $script_dir/job_key.pub | ssh $SSH_SUDO_USER@$host "cat >> ~/.ssh/authorized_keys"
    done
  else
    echo "[ERROR]: file 'job_key.pub' not exist in $script_dir/"
  fi
}

# Initialize flags
RUN_CERTS=false
RUN_REPO=false
RUN_PIP=false
RUN_KEY=false

# Parse command-line arguments
while getopts "crpk" opt; do
    case $opt in
        c) RUN_CERTS=true; echo "define -c 'certs'";;
        r) RUN_REPO=true; echo "define -r 'repo'";;
        p) RUN_PIP=true; echo "define -p 'pip'";;
        k) RUN_KEY=true; echo "define -k 'public_key'";;
        *) echo "Usage: $0 [-c] [-r] [-p] [-k]"; exit 1;;
    esac
done

# If no flags specified, run all setups
if ! $RUN_CERTS && ! $RUN_REPO && ! $RUN_PIP && ! $RUN_KEY; then
    RUN_CERTS=true
    RUN_REPO=true
    RUN_PIP=true
    RUN_KEY=true
    echo "No specific mode selected - running all setups"
fi

# Call the variable checking function
check_and_set_variables

# Display variable values for verification
echo "SSH_SUDO_USER: ${SSH_SUDO_USER}"
echo "NEXUS_FQDN: ${NEXUS_FQDN}"
echo "HOSTS_LIST: ${HOSTS_LIST}"

srv=$HOSTS_LIST

read -p "Press enter to continue: "

# Execute selected functions
if $RUN_CERTS; then setup_certs; fi
if $RUN_REPO; then setup_repo; fi
if $RUN_PIP; then setup_pip_repo; fi
if $RUN_KEY; then setup_public_key; fi

