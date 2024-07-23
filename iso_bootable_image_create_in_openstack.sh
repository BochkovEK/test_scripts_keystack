#!/bin/bash

#The script download bootable iso image and create image in openstack

script_dir=$(dirname $0)

[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The script download bootable iso image and create image in openstack (gpart-live.iso)
        "
          exit 0
          break ;;
        --) shift
          break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

# Check openrc file
check_and_source_openrc_file () {
    echo "Check openrc file and source it..."
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    if [ -z "$check_openrc_file" ]; then
        printf "%s\n" "${red}openrc file not found in $OPENRC_PATH - ERROR!${normal}"
        exit 1
    fi
    source $OPENRC_PATH
    #export OS_PROJECT_NAME=$PROJECT
}

check_and_source_openrc_file
iso=$script_dir/gpart-live.iso
if [ -f "$iso" ]; then
  echo "$iso exists in $script_dir"
else
  echo "download $iso for repo.itkey"
  wget https://repo.itkey.com/repository/images/gparted-live-1.5.0-6-amd64.iso -O $iso
fi

iso_in_openstack=$(openstack image list|grep gpart-live.iso)

if [ -z $iso_in_openstack ]; then
  echo "create bootable iso image in openstack"
  openstack image create gpart-live.iso \
    --file gpart-live.iso \
    --disk-format iso \
    --container-format bare \
    --property hw_rescue_device=cdrom \
    --property hw_rescue_bus=usb
else
  echo "bootable iso image already exists in openstack"
fi



