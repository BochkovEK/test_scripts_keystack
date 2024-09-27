#!/bin/bash

# The scrip deploy terraform from repo.itkey.com

# Deploy steps:
# 1) install terraform from repo.itkey.com

terraform_binary_name="terraform_1.8.5_linux_amd64"
image_name="ubuntu-20.04-server-cloudimg-amd64.img"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 13)
cyan=$(tput setaf 14)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
#magenta=$(tput setaf 5)

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir/utils
create_vms_with_module_dir=$script_dir/examples/create_vms_with_module

[[ -z $DONT_ASK ]] && DONT_ASK="false"


install_terraform () {
  echo -E "Terraform installing..."
  echo -E "Check terraform exists..."
  if [ ! -f /usr/local/bin/terraform ]; then
    echo -E "${yellow}Terraform does not exists${normal}"
    if [ ! $DONT_ASK = "true" ]; then
      export TS_YES_NO_QUESTION="Do you want to try install Terraform [Yes]:"
      bash $utils_dir/yes_no_answer.sh
    else
      TS_YES_NO_INPUT="true"
    fi
  fi
  if [ "$TS_YES_NO_INPUT" = "true" ]; then
    wget https://repo.itkey.com/repository/Terraform/$terraform_binary_name
    chmod 777 ./$terraform_binary_name
    mv $terraform_binary_name /usr/local/bin/terraform

    cat <<-EOF > ~/.terraformrc
provider_installation {
    network_mirror {
        url = "https://terraform-mirror.yandexcloud.net/"
        include = ["registry.terraform.io/*/*"]
    }
    direct {
        exclude = ["registry.terraform.io/*/*"]
    }
}
EOF
  else
    echo -E "${yellow}Terraform not installed${normal}"
    exit 0
  fi
}

create_cloud_config () {
  echo -E "Creating cloud.yml config in $create_vms_with_module_dir folder"
  cat <<-EOF > $create_vms_with_module_dir/clouds.yml
clouds:
  openstack:
    auth:
      auth_url: $OS_AUTH_URL
      username: "$OS_USERNAME"
      tenant_name: "$OS_TENANT_NAME"
      user_domain_name: "Default"
      password: $OS_PASSWORD
    region_name: "$OS_REGION_NAME"
    interface: "public"
    identity_api_version: 3
    cacert: "$OS_CACERT"
EOF
}

check_cloud_config () {
  echo -E "Check cloud.yml config in $create_vms_with_module_dir folder"
  bash $utils_dir/check_openrc.sh
  if [ ! -f $create_vms_with_module_dir/clouds.yml ]; then
    create_cloud_config
  else
    export TS_YES_NO_QUESTION="Do you want to overwrite $create_vms_with_module_dir/clouds.yml [Yes]:"
    bash $utils_dir/yes_no_answer.sh
  fi
  if [ "$TS_YES_NO_INPUT" = "true" ]; then
    create_cloud_config
  else
    echo -E "${yellow}$create_vms_with_module_dir/clouds.yml config not changed${normal}"
  fi
}

install_terraform
bash $utils_dir/openstack/check_openrs
check_cloud_config
# Create image
bash $utils_dir/openstack/create_image.sh $image_name
bash $utils_dir/openstack/create_pub_network.sh

