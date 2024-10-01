#!/bin/bash

# The scrip deploy terraform from repo.itkey.com

# Deploy steps:
# 1) install terraform from repo.itkey.com
# 2) Create cloud config in test_scripts_keystack/terraform folder
# 3) Create image from repo.itkey.com/images
# 4) Create pub_net


repo="https://repo.itkey.com/repository/bootstrap/terraform"
terraform_binary_name="terraform_1.8.5_linux_amd64"
image_name="ubuntu-20.04-server-cloudimg-amd64.img"
pub_net_name="pub_net"

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
examples_dir=$script_dir/exapmles
#create_vms_with_module_dir=$script_dir/examples/create_vms_with_module

[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $NETWORK ]] && NETWORK=$pub_net_name
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc


# Check command
check_command () {
  echo "Check $1 command..."
  command_exist="foo"
  if ! command -v $1 &> /dev/null; then
    command_exist=""
  fi
}

install_terraform () {
  echo -E "Terraform installing..."
  echo -E "Check terraform exists..."
  check_command terraform
  if [ -z $command_exist ]; then
    echo -E "${yellow}Terraform does not exists${normal}"
    if [ ! $DONT_ASK = "true" ]; then
      export TS_YES_NO_QUESTION="Do you want to try install Terraform [Yes]:"
      yes_no_input=$(bash $utils_dir/yes_no_answer.sh)
      echo $yes_no_input
    else
      yes_no_input="true"
    fi
  else
    echo -E "${green}Terraform already exists - ok!${normal}"
    return
  fi
  [ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]
  yes_no_input:   $yes_no_input
"
  if [ "$yes_no_input" = "true" ]; then
    wget $repo/$terraform_binary_name
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
  echo -E "Creating cloud.yml config in $script_dir folder"
#  bash $utils_dir/check_openrc.sh
  project_id=$(openstack project list|grep $OS_PROJECT_NAME|awk '{print $2}')
  cat <<-EOF > $script_dir/clouds.yml
clouds:
  openstack:
    auth:
      auth_url: $OS_AUTH_URL
      username: "$OS_USERNAME"
      tenant_name: "$OS_TENANT_NAME"
      user_domain_name: "Default"
      password: $OS_PASSWORD
      project_id: $project_id
    region_name: "$OS_REGION_NAME"
    interface: "public"
    identity_api_version: 3
    cacert: "$OS_CACERT"
EOF
  cat $script_dir/clouds.yml
}

check_cloud_config () {
  echo -E "Check cloud.yml config in $script_dir"
#  bash $utils_dir/check_openrc.sh
  if [ ! -f $script_dir/clouds.yml ]; then
    create_cloud_config
  else
    echo -E "${yellow}cloud.yml already exists in $script_dir${normal}"
    export TS_YES_NO_QUESTION="Do you want to overwrite $script_dir/clouds.yml [Yes]:"
    yes_no_input=$(bash $utils_dir/yes_no_answer.sh)
  fi
  if [ "$yes_no_input" = "true" ]; then
    create_cloud_config
  else
    echo -E "${yellow}$script_dir/clouds.yml config not changed${normal}"
  fi
}


install_terraform
export OPENRC_PATH=$OPENRC_PATH
if ! bash $utils_dir/check_openrc.sh; then
  exit 1
else
  source $OPENRC_PATH
fi

[ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]
  OS_PROJECT_DOMAIN_NAME:   $OS_PROJECT_DOMAIN_NAME
  OS_USER_DOMAIN_NAME:      $OS_USER_DOMAIN_NAME
  OS_PROJECT_NAME:          $OS_PROJECT_NAME
  OS_TENANT_NAME:           $OS_TENANT_NAME
  OS_USERNAME:              $OS_USERNAME
  OS_PASSWORD:              $OS_PASSWORD
  OS_AUTH_URL:              $OS_AUTH_URL
  OS_INTERFACE:             $OS_INTERFACE
  OS_ENDPOINT_TYPE:         $OS_ENDPOINT_TYPE
  OS_IDENTITY_API_VERSION:  $OS_IDENTITY_API_VERSION
  OS_REGION_NAME:           $OS_REGION_NAME
  OS_AUTH_PLUGIN:           $OS_AUTH_PLUGIN
  OS_DRS_ENDPOINT_OVERRIDE: $OS_DRS_ENDPOINT_OVERRIDE
"
check_cloud_config
# Create image
if ! bash $utils_dir/openstack/create_image.sh $image_name; then
  exit 1
fi
# Create network
export NETWORK=$NETWORK
if ! bash $utils_dir/openstack/create_pub_network.sh; then
  exit 1
fi

echo -E "${green}
Terraform installed - ok!
cloud.yml config in $script_dir - ok!
Image $image_name created - ok!
Network $pub_net_name created - ok!
${normal}"
echo "
You can create resources using terraform.
  1) Create <name>.auto.tfvars configs and copy clouds.yml from $script_dir to the following 'examples' dir:"
dirs=$(ls -d $examples_dir/*/)
for dir in $dirs; do echo $dir; done
echo "
  2) Run following commands from 'examples' dir to create resources:
    terraform init
    terraform plan -var-file \"<name>.auto.tfvars\"
    terraform apply
    type \"yes\"

Read more: https://github.com/BochkovEK/test_scripts_keystack/tree/master/terraform
"


