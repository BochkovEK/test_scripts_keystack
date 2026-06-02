#!/bin/bash

# The script create image.
# To create:
#   1) curl -o https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img
#   2) bash ~/test_scripts_keystack/batch_openstack_cli/create_image_from_file.sh ubuntu-22.04-server-cloudimg-amd64.img


#SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if the image filename argument is provided
if [ -z "$1" ]; then
  echo "Error: Please specify the image filename."
  echo "Usage: $0 ubuntu-20.04-server-cloudimg-amd64.img"
  exit 1
fi

IMAGE_NAME=$(basename "$1")
IMAGE_PATH=$(realpath "$1")

if [ ! -f "${IMAGE_PATH}" ]; then
  echo "Error: File ${IMAGE_PATH} does not exist."
  exit 1
fi

# Create the image in OpenStack using the provided argument
openstack image create \
  --file "${IMAGE_PATH}" \
  --container-format bare \
  --disk-format qcow2 \
  --public \
  --min-disk 5 \
  --min-ram 1024 \
  "${IMAGE_NAME}"
