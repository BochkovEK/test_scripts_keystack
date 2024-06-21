#!/bin/bash

#The script download bootable iso image and create image in openstack

script_dir=$(dirname $0)

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

wget https://repo.itkey.com/repository/images/gparted-live-1.5.0-6-amd64.iso -O $script_dir/gpart-live.iso
openstack image create gpart-live.iso \
  --file gparted-live-1.5.0-6-amd64.iso \
  --disk-format iso \
  --container-format bare \
  --property hw_rescue_device=cdrom \
  --property hw_rescue_device=cdrom \
  --property hw_rescue_bus=usb



