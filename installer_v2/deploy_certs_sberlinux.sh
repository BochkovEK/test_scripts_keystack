#!/bin/bash

# To gen job_key.pub from job_key from vault
#ssh-keygen -y -f job_key > job_key.pub

ssh_sudo_user="kolla"
ca_crt_file="mutiple-node/certs/ca.crt"
env_file_name=".deploy_certs_env"
#gitlab_public_key_path="config/gitlab_key.pub"
gitlab_job_public_key="job_key.pub"
#installer_root_folder="/installer"
installer_distribution_folder="$HOME/installer"
required_file=(
  "pip.conf"
  "sberlinux-9.repo"
)


# Determine the directory where the script is located
script_dir=$(dirname "$(readlink -f "$0")")

# Function to check and set variables
check_and_set_variables() {
    # Check if environment variables exist
    if [[
          -z "${SSH_SUDO_USER}" ||
          -z "${HOSTS_LIST}" ||
          -z "${INSTALLER_DISTRIBUTION_FOLDER}" ||
          -z "${GITLAB_JOB_PUBLIC_KEY_PATH}" ||
          -z "${NEXUS_FQDN}" ||
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

        while [[ -z "${HOSTS_LIST}" ]]; do
          HOSTS_LIST=$(cat /etc/hosts | grep -E "ctrl|comp|net-" | awk '{print $1}')
          if [[ -z "${HOSTS_LIST}" ]]; then
            read -p "Enter list of hosts (space-separated): " HOSTS_LIST
          fi
        done

        while [[ -z "${INSTALLER_DISTRIBUTION_FOLDER}" ]]; do
          read -rp "Enter installer distribution folder [$installer_distribution_folder]: " INSTALLER_DISTRIBUTION_FOLDER
          INSTALLER_DISTRIBUTION_FOLDER=${INSTALLER_DISTRIBUTION_FOLDER:-"$installer_distribution_folder"}
        done

        while [[ -z "${GITLAB_JOB_PUBLIC_KEY_PATH}" ]]; do
          read -rp "Enter gitlab job public key [$installer_distribution_folder/$gitlab_job_public_key]: " GITLAB_JOB_PUBLIC_KEY_PATH
          GITLAB_JOB_PUBLIC_KEY_PATH=${GITLAB_JOB_PUBLIC_KEY_PATH:-"$installer_distribution_folder/$gitlab_job_public_key"}
        done

        while [[ -z "${NEXUS_FQDN}" ]]; do
          read -p "Enter Nexus service FQDN: " NEXUS_FQDN
        done

        while [[ -z "${CA_CRT_PATH}" ]]; do
          read -rp "Enter CA cert path [$installer_distribution_folder/$ca_crt_file]: " CA_CRT_PATH
          CA_CRT_PATH=${CA_CRT_PATH:-"$installer_distribution_folder/$ca_crt_file"}
        done

        # Save variables to file
        echo > "${script_dir}/$env_file_name"
        {
          echo "export SSH_SUDO_USER=\"${SSH_SUDO_USER}\"";
          echo "export HOSTS_LIST=\"${HOSTS_LIST}\"";
          echo "export INSTALLER_DISTRIBUTION_FOLDER=\"${INSTALLER_DISTRIBUTION_FOLDER}\"";
          echo "export GITLAB_JOB_PUBLIC_KEY_PATH=\"${GITLAB_JOB_PUBLIC_KEY_PATH}\"";
          echo "export NEXUS_FQDN=\"${NEXUS_FQDN}\"";
          echo "export CA_CRT_PATH=\"${CA_CRT_PATH}\"";
        } >> "${script_dir}/$env_file_name"
    fi

    # Verify that variables are now set
    if [[
          -z "${SSH_SUDO_USER}" ||
          -z "${HOSTS_LIST}" ||
          -z "${INSTALLER_DISTRIBUTION_FOLDER}" ||
          -z "${GITLAB_JOB_PUBLIC_KEY_PATH}" ||
          -z "${NEXUS_FQDN}" ||
          -z "${CA_CRT_PATH}"
       ]]; then
        echo "Error: Required variables are not set."
        exit 1
    fi
}

# SED init configuration
sed_init_config () {
  #source /installer/config/settings

  for file in "${required_file[@]}"; do
    if [ ! -f ${INSTALLER_DISTRIBUTION_FOLDER}/$file ]; then
      echo "Error: Required file $file not exists in ${INSTALLER_DISTRIBUTION_FOLDER}/ "
      exit 1
    fi
  done
  echo "Sed repos templates..."
  for file in "${required_file[@]}"; do
    sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" ${INSTALLER_DISTRIBUTION_FOLDER}/$file
    echo "cat $file:"
    cat ${INSTALLER_DISTRIBUTION_FOLDER}/$file
  done
}

# Functions for each mode
setup_certs() {
  echo "Configuring certificates..."
  for host in $srv; do
    sudo sh -c "cat $CA_CRT_PATH" |ssh $SSH_SUDO_USER@$host "sudo tee /etc/pki/ca-trust/source/anchors/ca.crt > /dev/null"
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

send_gitlab_job_public_key_to_nodes () {
  for host in $HOSTS_LIST; do
    cat $1 | ssh $SSH_SUDO_USER@$host "cat >> ~/.ssh/authorized_keys"
  done
}

setup_public_key() {
  echo "Configuring gitlab job_key.pub..."
  if [[ -f "${GITLAB_JOB_PUBLIC_KEY_PATH}" ]]; then
      send_gitlab_job_public_key_to_nodes $GITLAB_JOB_PUBLIC_KEY_PATH
  else
    echo "[ERROR]: file '$GITLAB_JOB_PUBLIC_KEY_PATH' not exist"
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
echo "HOSTS_LIST:
${HOSTS_LIST}"

srv=$HOSTS_LIST

read -p "Press enter to continue: "

# Execute selected functions
if $RUN_CERTS; then setup_certs; fi
if $RUN_REPO; then setup_repo; fi
if $RUN_PIP; then setup_pip_repo; fi
if $RUN_KEY; then setup_public_key; fi

