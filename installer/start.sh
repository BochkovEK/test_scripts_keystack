#!/bin/bash

# The script launches a custom installer and adds the original one to backup folder (~/installer/backup)
# Before starting be ensure that /etc/hosts has strings:
# <ip_lcm> <lcm-nexus>.<domain> <lcm-gitlab>.<domain> gitlab-runner.<domain> <lcm-vault>.<domain> <lcm-netbox>.<domain>
# 10.224.129.239 ebochkov-keystack-lcm-01 lcm-gitlab.test.domain gitlab-runner.test.domain lcm-vault.test.domain lcm-netbox.test.domain lcm-nexus.test.domain
# 10.224.129.234 ebochkov-keystack-comp-01 comp-01 nexus.test.domain
# startup example: bash start.sh custom - execute custom_installer.sh

CUSTOM_INSTALLER=custom_installer.sh
INSTALL_DIR=$HOME/installer
BACKUP_FOLDER=$INSTALL_DIR/backup

script_dir=$(dirname $0)

mkdir -p $BACKUP_FOLDER
[[ ! -f $BACKUP_FOLDER/installer.sh ]] && { echo "Make $INSTALL_DIR/installer.sh backup to $BACKUP_FOLDER"; cp $INSTALL_DIR/installer.sh $BACKUP_FOLDER; }
echo "$BACKUP_FOLDER:"
ls -la $BACKUP_FOLDER

echo "Copy custom_installer.sh to $INSTALL_DIR"
cp $script_dir/$CUSTOM_INSTALLER $INSTALL_DIR

echo "Set installer_envs:"
[[ -f $script_dir/installer_envs ]] && { cat $script_dir/installer_envs; echo; source $script_dir/installer_envs; }

cd $INSTALL_DIR || { echo "$INSTALL_DIR not found"; exit 1; }
echo "Current dir: $PWD"

if [ "$1" = custom ]; then
  bash ./custom_installer.sh
else
  bash ./installer.sh
fi

