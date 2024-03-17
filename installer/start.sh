#!/bin/bash

#The script launches a custom installer and adds the original one to backup folder (~/installer/backup)

CUSTOM_INSTALLER=custom_installer.sh
INSTALL_DIR=$HOME/installer
BACKUP_FOLDER=$INSTALL_DIR/backup

script_dir=$(dirname $0)

mkdir -p $BACKUP_FOLDER
[[ ! -f $BACKUP_FOLDER/installer.sh ]] && { echo "Make installer backup to $BACKUP_FOLDER"; cp $INSTALL_DIR/installer.sh script_dir; }

echo "Copy custom_installer.sh to $INSTALL_DIR"
cp $script_dir/$CUSTOM_INSTALLER $INSTALL_DIR

cd $INSTALL_DIR || { echo "$INSTALL_DIR not found"; exit 1; }
echo "Current dir: $PWD"
bash ./custom_installer.sh

