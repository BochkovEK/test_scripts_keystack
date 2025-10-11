#!/bin/bash

# The script create image.
# To create:
#   1) curl -o ~/test_scripts_keystack/utils/openstack/ubuntu-22.04-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img
#   2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh ubuntu-22.04-server-cloudimg-amd64.img
# OR
#    1) export IMAGE_SOURCE="https://cloud-images.ubuntu.com/releases/focal/release"
#    2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh ubuntu-20.04-server-cloudimg-amd64.img
#     or
#    1) export IMAGE_SOURCE="http://cloud-images-archive.ubuntu.com/releases/noble/release-20240523.1"
#    2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh ubuntu-24.04-server-cloudimg-amd64.img
#     or
#    2) bash ~/test_scripts_keystack/utils/openstack/create_image.sh cirros-0.6.2-x86_64-disk.img

# Colors
normal=$(tput sgr0)
green=$(tput setaf 2)
red=$(tput setaf 1)
blue=$(tput setaf 4)
yellow=$(tput setaf 3)

script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
yes_no_answer_script="yes_no_answer.sh"

default_api_version="2.74"

# Default values
[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $IMAGE_SOURCE ]] && IMAGE_SOURCE="https://repo.itkey.com/repository/images"
[[ -z $IMAGE ]] && IMAGE=$1
[[ -z $IMAGE_DIR ]] && IMAGE_DIR="$HOME/images"
[[ -z $MIN_DISK ]] && MIN_DISK=""
[[ -z $API_VERSION ]] && API_VERSION="$default_api_version"
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"

# External scripts array
external_scripts=(
    "$utils_dir/$yes_no_answer_script"
)

# Function to load external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            echo -e "${red}Error: Required script not found: $script_path${normal}"
            exit 1
        fi
        if [ ! -r "$script_path" ]; then
            echo -e "${red}Error: Script not readable: $script_path${normal}"
            exit 1
        fi
        echo -e "${blue}Loading external script: $(basename "$script_path")${normal}"
        source "$script_path"
    done
}

# Universal confirmation function with DONT_ASK support
confirm_action_universal() {
    local message="$1"
    local default_answer="${2:-"Yes"}"

    if [[ $DONT_ASK = "true" ]]; then
        echo -e "${green}Auto-confirmed (DONT_ASK): $message${normal}"
        return 0
    fi

    # Use external confirmation function
    confirm_action_external "$message" "$default_answer"
}

error_output() {
    if [ -n "${warning_message}" ]; then
        printf "%s\n" "${yellow}$warning_message${normal}"
        warning_message=""
    fi
    printf "%s\n" "${red}$error_message - ERROR${normal}"
    exit 1
}

check_and_source_openrc_file() {
    if bash $utils_dir/$check_openrc_script &> /dev/null; then
        openrc_file=$(bash $utils_dir/$check_openrc_script)
        source $openrc_file
    else
        bash $utils_dir/$check_openrc_script
        exit 1
    fi
}

check_openstack_cli() {
    if [[ $CHECK_OPENSTACK = "true" ]]; then
        if ! bash $utils_dir/$check_openstack_cli_script &> /dev/null; then
            echo -e "${red}Failed to check openstack cli - ERROR${normal}"
            exit 1
        fi
    fi
}

download_image() {
    local image_name="$1"

    echo -e "${yellow}File $image_name does not exist locally${normal}"

    if [ -z "$IMAGE_SOURCE" ]; then
        warning_message="Global variable \$IMAGE_SOURCE is not defined"
        error_message="Image $image_name cannot be downloaded"
        error_output
    fi

    if confirm_action_universal "Do you want to download $image_name from source: $IMAGE_SOURCE?" "Yes"; then
        echo "Downloading $image_name from $IMAGE_SOURCE..."
        if curl -o $IMAGE_DIR/$image_name $IMAGE_SOURCE/$image_name; then
            echo -e "${green}Successfully downloaded $image_name${normal}"
            return 0
        else
            error_message="Failed to download $image_name from $IMAGE_SOURCE"
            error_output
        fi
    else
        error_message="Image $image_name download cancelled by user"
        error_output
    fi
}

create_image_in_openstack() {
    local image_name="$1"

    echo "Creating image \"$image_name\" in OpenStack..."

    if openstack image create "$image_name" \
        --disk-format qcow2 \
        --container-format bare \
        --public \
        $MIN_DISK --file $IMAGE_DIR/$image_name; then
        echo -e "${green}Image $image_name created successfully${normal}"
        return 0
    else
        return 1
    fi
}

verify_image_creation() {
    local image_name="$1"
    local max_attempts=30
    local attempt=1

    echo "Verifying image creation..."

    while [ $attempt -le $max_attempts ]; do
        local image_exists_in_openstack=$(openstack image list | grep -m 1 "$image_name" | awk '{print $2}')

        if [ -n "$image_exists_in_openstack" ]; then
            echo -e "${green}Image $image_name successfully created in OpenStack - OK!${normal}"
            return 0
        fi

        echo "Attempt $attempt/$max_attempts: Image not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done

    error_message="Image $image_name creation verification timeout"
    return 1
}

create_image() {
    echo "Checking if image \"$IMAGE\" exists in OpenStack..."

    local image_exists_in_openstack=$(openstack image list | grep -m 1 "$IMAGE" | awk '{print $2}')
    [ "$TS_DEBUG" = true ] && echo -e "image_exists_in_openstack: $image_exists_in_openstack"

    if [ -n "$image_exists_in_openstack" ]; then
        echo -e "${green}Image \"$IMAGE\" already exists in OpenStack - OK!${normal}"
        exit 0
    fi

    echo -e "${yellow}Image \"$IMAGE\" not found in OpenStack${normal}"

    # Confirm image creation
    if ! confirm_action_universal "Do you want to create image: $IMAGE?" "Yes"; then
        echo -e "${yellow}Image $IMAGE creation cancelled${normal}"
        exit 0
    fi

    # Prepare local image directory
    mkdir -p $IMAGE_DIR

    # Check if image file exists locally
    if [ -f $script_dir/"$IMAGE" ]; then
        echo "Copying image from script directory to $IMAGE_DIR..."
        cp $script_dir/"$IMAGE" $IMAGE_DIR/$IMAGE
    fi

    if [ -f $IMAGE_DIR/"$IMAGE" ]; then
        echo -e "${green}Local file $IMAGE exists - OK!${normal}"
    else
        # Download image if not exists locally
        download_image "$IMAGE"
    fi

    # Create image in OpenStack
    if create_image_in_openstack "$IMAGE"; then
        verify_image_creation "$IMAGE"
    else
        error_message="Failed to create image $IMAGE in OpenStack"
        error_output
    fi
}

# Main execution
echo "$script_name script started..."

# Validate input parameters
if [ -z "$IMAGE" ]; then
    echo "Available images from repo.itkey.com:"
    echo "Executing: curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json' | jq '.items[]|.name'"

    if ! curl -X 'GET' 'https://repo.itkey.com/service/rest/v1/search?repository=images&name=*' -H 'accept: application/json' 2>/dev/null | jq '.items[]|.name' 2>/dev/null; then
        echo -e "${yellow}Could not fetch image list from repository${normal}"
    fi

    error_message="You must define image name as script parameter"
    error_output
fi

# Debug information
if [ "$TS_DEBUG" = true ]; then
    echo -e "
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
  ---
  IMAGE:                    $IMAGE
  IMAGE_SOURCE:             $IMAGE_SOURCE
  IMAGE_DIR:                $IMAGE_DIR
  DONT_ASK:                 $DONT_ASK
"
fi

# Load external scripts and execute main logic
load_external_scripts
check_openstack_cli
check_and_source_openrc_file
create_image

echo -e "${green}Script completed successfully!${normal}"