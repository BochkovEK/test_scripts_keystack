#!/bin/bash

# Script for creating VMs in OpenStack environment
# Supports batch creation and maintains state files for cleanup

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

# Default constants
default_flavor="4c-4r"
default_key_name="key_test"
default_project="admin"
default_test_user="admin"
default_role="admin"
default_api_version="2.74"
default_network="pub_net"
default_security_group_name="test_security_group"
default_volume_size="5"
default_vm_base_name="TEST_VM_FROM_SCRIPT"

# Script_dir, current folder
script_dir=$(dirname $0)
utils_dir=$script_dir/utils
yes_no_answer_script="yes_no_answer.sh"
check_openrc_script="check_openrc.sh"
create_pub_network_script="openstack/create_pub_network.sh"
create_image_script_script="openstack/create_image.sh"
check_ssh_connectivity_script="check_ssh_connectivity.sh"
get_nodes_list_script="get_nodes_list.sh"
config_file=".vm_creation_config.env"
cleanup_file=".vm_cleanup_state.env"

# External scripts array
external_scripts=(
    "$utils_dir/$yes_no_answer_script"
    "$utils_dir/$check_ssh_connectivity_script"
)

# Constants
TIMEOUT_BEFORE_NEXT_CREATION=5
UBUNTU_IMAGE_NAME="ubuntu-20.04-server-cloudimg-amd64.img"
CIRROS_IMAGE_NAME="cirros-0.6.3-x86_64-disk.img"

# Default values
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc
[[ -z $VM_QTY ]] && VM_QTY="1"
[[ -z $IMAGE ]] && IMAGE=$UBUNTU_IMAGE_NAME
[[ -z $FLAVOR ]] && FLAVOR="$default_flavor"
[[ -z $NO_KEY ]] && NO_KEY="false"
[[ -z $KEY_NAME ]] && KEY_NAME="$default_key_name"
[[ -z $HYPERVISOR_HOSTNAME ]] && HYPERVISOR_HOSTNAME=""
[[ -z $PROJECT ]] && PROJECT="$default_project"
[[ -z $API_VERSION ]] && API_VERSION="$default_api_version"
[[ -z $NETWORK ]] && NETWORK="$default_network"
[[ -z $SECURITY_GR ]] && SECURITY_GR="$default_security_group_name"
[[ -z $VOLUME_SIZE ]] && VOLUME_SIZE="$default_volume_size"
[[ -z $VM_BASE_NAME ]] && VM_BASE_NAME="$default_vm_base_name"
[[ -z $TEST_USER ]] && TEST_USER="$default_test_user"
[[ -z $ROLE ]] && ROLE="$default_role"
[[ -z $ADD_KEY ]] && ADD_KEY=""
[[ -z $BATCH ]] && BATCH="false"
[[ -z $DONT_CHECK ]] && DONT_CHECK="false"
[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $WAIT_FOR_CREATED ]] && WAIT_FOR_CREATED="true"
[[ -z $USE_ENV_FILE ]] && USE_ENV_FILE="false"
[[ -z $VIRTUAL_ENV ]] && VIRTUAL_ENV="$script_dir"

# Function to display help information
show_help() {
    echo -E "
    OpenStack VM Creation Script

    Usage: $0 [OPTIONS]

    Options:
      -orc          -openrc_path    <openrc_path>
      -q,           -qty            <number_of_VMs>
      -i,           -image          <image_name>
                                  The script can try to download and upload cirros and ubuntu images.
                                  For this you need to define -i cirros\ubuntu
      -f,           -flavor         <flavor_name>
      -k,           -key            <key_name>
      -nk           -no_key         disable key pair (without parameter)
      -hv,          -hypervisor     <hypervisor_name>
      -net,         -network        <network_name>
      -v,           -volume_size    <volume_size_in_GB>
      -n,           -name           <vm_base_name>
      -p,           -project        <project_id>
      -t                            <time_out_between_VM_create>
      -dont_check_osc               disable check openstack cli (without parameter)
      -dont_check                   disable resource availability checks (without value)
      -da,          -dont_ask       all actions will be performed automatically (without value)
      -add                          <add command key>
                                  Examples:
                                    -add \"--availability-zone \$az_name\"
                                    -add \"--hint group=\$anti_aff_gr\"
      -b,           -batch          creating VMs without a timeout (without value)
      -debug,                       enabled debug output (without parameter)
      -wait,                        wait for vms created <true\false>
      -uef,         -use_env_file   use env file $config_file variables by default
      -ef,          -envs_folder    directory where envs configs \'$config_file\', \'$cleanup_file\' will be saved and used

    State Files:
      $config_file    - creation configuration parameters
      $cleanup_file   - resource IDs for cleanup operations
    "
}

# Function to use config file
use_env_file () {
    while [ -n "$1" ]; do
        case "$1" in
            -uef|-use_env_file) USE_ENV_FILE="true"
                echo "Found the -use_env_file. Using config file $config_file by default"
                ;;
            --) shift
                break
                ;;
        esac
        shift
    done

    if [ $USE_ENV_FILE = "true" ]; then
        echo "HERE"
        check_and_source_config_file
    fi

}

# Parse command line arguments
parse_arguments() {
    while [ -n "$1" ]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            -t|-timeout) timeout_before_next_creation="$2"
                echo "Found the -timeout option with value $timeout_before_next_creation"
                shift ;;
            -q|-qty) qty="$2"
                echo "Found the -qty option with value $qty"
                shift ;;
            -i|-image) image="$2"
                echo "Found the -image option with value $image"
                shift ;;
            -f|-flavor) flavor="$2"
                echo "Found the -flavor option with value $flavor"
                shift;;
            -k|-key) key_name="$2"
                echo "Found the -key_name option with value $key_name"
                shift;;
            -nk|no_key) no_key="true"
                echo "Found the -no_name option"
                ;;
            -hv|-hypervisor) hyper_name="$2"
                echo "Found the -hyper_name option with value $hyper_name"
                shift ;;
            -p|-project) project="$2"
                echo "Found the -project option with value $project"
                shift ;;
            -net|-network) network="$2"
                echo "Found the -network option with value $network"
                shift ;;
            -v|volume_size) volume_size="$2"
                echo "Found the -volume_size option with value $volume_size"
                shift ;;
            -orc|-openrc_path) openrc_path="$2"
                echo "Found the -openrc_path option with value $openrc_path"
                shift ;;
            -n|-name) name="$2"
                echo "Found the -name option with value $name"
                shift ;;
            -dont_check_osc) check_openstack="false"
                echo "Found the -dont_check_osc. Openstack cli check disabled"
                ;;
            -dont_check) DONT_CHECK="true"
                echo "Found the -dont_check. Resource availability checks are disabled"
                ;;
            -da|-dont_ask) dont_ask="true"
                echo "Found the -dont_ask. All actions will be performed automatically"
                ;;
            -uef|-use_env_file) USE_ENV_FILE="true"
                echo "Found the -use_env_file. Using config file $config_file by default"
                ;;
            -ef|-envs_folder) VIRTUAL_ENV="$2"
                echo "Found the -envs_folder. Using envs config folder $VIRTUAL_ENV"
                shift ;;
            -b|-batch) batch=true
                echo "Found the -batch. VMs will be created without a timeout"
                ;;
            -add) add_key="$2"
                echo "Found the -add option with value $add_key"
                shift ;;
            -wait) wait_for_created="$2"
                echo "Found the -wait option with value $wait_for_created"
                shift ;;
            -debug) ts_debug="true"
                echo "Found the -debug option"
                ;;
            --) shift
                break ;;
            *) echo "$1 is not an option";;
        esac
        shift
    done
}

# Function to get yes/no answer from user
yes_no_answer() {
    local question="$1"
    local default_answer="${2:-"Yes"}"

    # Use external confirmation function
    confirm_action_external "$question" "$default_answer"
}

# Function error output
error_output() {
    local message="$1"
    echo -e "${red}ERROR: $message${normal}" >&2
    exit 1
}

# Function warning output
warning_output() {
    local message="$1"
    echo -e "${yellow}WARNING: $message${normal}" >&2
}

# Check OpenStack CLI
check_openstack_cli () {
    if ! command -v openstack &> /dev/null; then
        echo -e "${red}OpenStack CLI not found${normal}"
        exit 1
    fi
}

# Check and source config file
check_and_source_config_file () {
    echo "Checking config file and sourcing it..."

    if [ -f "$VIRTUAL_ENV/$config_file" ]; then
        source "$VIRTUAL_ENV/$config_file"
        echo -e "${green}Config file loaded: $VIRTUAL_ENV/$config_file${normal}"
    fi
}

# Initialize cleanup state file with proper structure
init_cleanup_state_file () {
    if [ ! -f "$VIRTUAL_ENV/$cleanup_file" ]; then
        echo "Initializing cleanup state file..."
        cat <<EOF > "$VIRTUAL_ENV/$cleanup_file"
# OpenStack VM Cleanup State
# Created: $(date)

# Batch resources will be added below
EOF
        echo -e "${green}Cleanup state file created: $VIRTUAL_ENV/$cleanup_file${normal}"
    fi
}

# Update cleanup state with new batch
update_cleanup_state () {
    local batch_num="$1"
    local vm_ids="$2"
    local volume_ids="$3"  # Can be empty

    echo "Updating cleanup state for batch $batch_num..."

    # Check if batch already exists
    if grep -q "CREATED_VM_IDS_BATCH_$batch_num" "$VIRTUAL_ENV/$cleanup_file"; then
        echo -e "${yellow}Batch $batch_num already exists in cleanup file${normal}"
        return 1
    fi

    # Add batch header
    echo "" >> "$VIRTUAL_ENV/$cleanup_file"
    echo "# Batch $batch_num" >> "$VIRTUAL_ENV/$cleanup_file"

    # Add VM IDs
    echo "export CREATED_VM_IDS_BATCH_${batch_num}=\"$vm_ids\"" >> "$VIRTUAL_ENV/$cleanup_file"

    # Add volume IDs only if they exist
    if [ -n "$volume_ids" ]; then
        echo "export CREATED_BOOT_VOLUMES_BATCH_${batch_num}=\"$volume_ids\"" >> "$VIRTUAL_ENV/$cleanup_file"
    else
        echo "# Volume IDs will be collected during cleanup" >> "$VIRTUAL_ENV/$cleanup_file"
    fi

    # Add reusable resources only if they don't exist
#    if [ -n "$SECURITY_GR_ID" ] && ! grep -q "CREATED_SECURITY_GROUP_ID" "$VIRTUAL_ENV/$cleanup_file"; then
    if [ -n "$SECURITY_GR_ID" ]; then
        echo "export CREATED_SECURITY_GROUP_ID_BATCH_${batch_num}=\"$SECURITY_GR_ID\"" >> "$VIRTUAL_ENV/$cleanup_file"
    fi

    if [ -n "$FLAVOR" ] && [ "$NEW_FLAVOR_CREATED" = "true" ] && ! grep -q "${FLAVOR}_${PROJECT}" "$VIRTUAL_ENV/$cleanup_file"; then
        echo "export CREATED_FLAVOR_NAME_BATCH_${batch_num}=\"${FLAVOR}_${PROJECT}\"" >> "$VIRTUAL_ENV/$cleanup_file"
    fi

    # Add keypair with user info only if it doesn't exist
    if [ -n "$KEY_NAME" ] && [ -n "$TEST_USER" ]; then
        local keypair_user="$KEY_NAME:$TEST_USER"
        if ! grep -q "CREATED_KEYPAIR_NAME_USER.*\"$keypair_user\"" "$VIRTUAL_ENV/$cleanup_file"; then
            echo "export CREATED_KEYPAIR_NAME_USER_BATCH_${batch_num}=\"$keypair_user\"" >> "$VIRTUAL_ENV/$cleanup_file"
        fi
    fi

    echo -e "${green}Cleanup state updated with batch $batch_num${normal}"
    return 0
}

# Get security group ID if it exists
get_security_group_id() {
    if [ -z "$PROJ_ID" ]; then
        # Get project ID quietly
        PROJ_ID=$(openstack project show "$PROJECT" -c id -f value 2>/dev/null)
        if [ -z "$PROJ_ID" ]; then
            echo ""
            return 1
        fi
    fi

    SECURITY_GR_ID=$(openstack security group list | grep -E "($SECURITY_GR(.)*$PROJ_ID)" | head -1 | awk '{print $2}')
    echo "$SECURITY_GR_ID"
}

# Get next available batch number
get_next_batch_number () {
    local last_batch=0

    if [ -f "$VIRTUAL_ENV/$cleanup_file" ]; then
        # Find the highest batch number in the file
        last_batch=$(grep -o 'CREATED_VM_IDS_BATCH_[0-9]*' "$VIRTUAL_ENV/$cleanup_file" | \
                    grep -o '[0-9]*' | sort -n | tail -1)
    fi

    echo $((last_batch + 1))
}

# Write configuration to file
write_config_file () {
    echo "Writing configuration to $VIRTUAL_ENV/$config_file..."

    if [ $NO_KEY = "true" ]; then
        key_name_init_param="NO keypair"
    else
        key_name_init_param="$KEY_NAME"
    fi

    cat <<EOF > "$VIRTUAL_ENV/$config_file"
# VM Creation Configuration
export OPENRC_PATH='$OPENRC_PATH'
export VM_BASE_NAME='$VM_BASE_NAME'
export VM_QTY='$VM_QTY'
export IMAGE='$IMAGE'
export FLAVOR='$FLAVOR'
export SECURITY_GR='$SECURITY_GR'
export KEY_NAME='$key_name_init_param'
export PROJECT='$PROJECT'
export TEST_USER='$TEST_USER'
export ROLE='$ROLE'
export HYPERVISOR_HOSTNAME='$HYPERVISOR_HOSTNAME'
export NETWORK='$NETWORK'
export VOLUME_SIZE='$VOLUME_SIZE'
export API_VERSION='$API_VERSION'
export ADD_KEY='$ADD_KEY'
export BATCH='$BATCH'
export TS_DEBUG='$TS_DEBUG'
export WAIT_FOR_CREATED='$WAIT_FOR_CREATED'
export VIRTUAL_ENV='$VIRTUAL_ENV'
EOF

    echo -e "${green}Configuration saved to $VIRTUAL_ENV/$config_file${normal}"
}

# Assign variables from command line arguments
assign_vars_from_startup_keys () {
    [[ -n $timeout_before_next_creation ]] && TIMEOUT_BEFORE_NEXT_CREATION=$timeout_before_next_creation
    [[ -n $qty ]] && VM_QTY=$qty
    [[ -n $image ]] && IMAGE=$image
    [[ -n $flavor ]] && FLAVOR=$flavor
    [[ -n $key_name ]] && KEY_NAME=$key_name
    [[ -n $no_key ]] && NO_KEY=$no_key
    [[ -n $hyper_name ]] && HYPERVISOR_HOSTNAME=$hyper_name
    [[ -n $project ]] && PROJECT=$project
    [[ -n $network ]] && NETWORK=$network
    [[ -n $volume_size ]] && VOLUME_SIZE=$volume_size
    [[ -n $openrc_path ]] && OPENRC_PATH=$openrc_path
    [[ -n $name ]] && VM_BASE_NAME=$name
    [[ -n $check_openstack ]] && CHECK_OPENSTACK=$check_openstack
    [[ -n $dont_check ]] && DONT_CHECK=$dont_check
    [[ -n $dont_ask ]] && DONT_ASK=$dont_ask
    [[ -n $batch ]] && BATCH=$batch
    [[ -n $add_key ]] && ADD_KEY=$add_key
    [[ -n $wait_for_created ]] && WAIT_FOR_CREATED=$wait_for_created
    [[ -n $ts_debug ]] && TS_DEBUG=$ts_debug
}

# Display initial parameters
output_of_initial_parameters () {
    if [ $NO_KEY = "true" ]; then
        key_name_init_param="NO keypair"
    else
        key_name_init_param="$KEY_NAME"
    fi

    echo -E "
${green}VM Creation Configuration:${normal}
    OPENRC file path:                 $OPENRC_PATH
    VM base name:                     $VM_BASE_NAME
    Number of VMs:                    $VM_QTY
    Image name:                       $IMAGE
    Flavor name:                      $FLAVOR
    Security group:                   $SECURITY_GR
    Key name:                         $key_name_init_param
    Project:                          $PROJECT
    User:                             $TEST_USER
    User role:                        $ROLE
    Hypervisor name:                  $HYPERVISOR_HOSTNAME
    Network name:                     $NETWORK
    Volume size:                      $VOLUME_SIZE
    OS compute api version:           $API_VERSION
    Addition key:                     $ADD_KEY
    Creating VMs without a timeout:   $BATCH
    Debug:                            $TS_DEBUG
    Dont check resources exists:      $DONT_CHECK
    Wait for creating:                $WAIT_FOR_CREATED
    Output envs config file:          $VIRTUAL_ENV/$config_file
    Cleanup envs config file:         $VIRTUAL_ENV/$cleanup_file
        "

#    [[ ! $DONT_ASK = "true" ]] && { read -p "Press enter to continue: "; }
    read -p "Press enter to continue: "
}

# Check and source openrc file
check_and_source_openrc_file () {
    if openrc_file=$(bash $utils_dir/$check_openrc_script 2>/dev/null); then
        source "$openrc_file"
        return 0
    fi
    exit 1
}

# Check command availability
check_command () {
    echo "Check $1 command..."
    command_exist="foo"
    if ! command -v $1 &> /dev/null; then
        command_exist=""
    fi
}

# Function to get nodes list using external script
get_nodes_list() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
      nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$*\")"
    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result: $nodes_result
    "

    # Check for errors in node list
    if [ -z "$nodes_result" ]; then
        error_output "Failed to determine node list"
    elif echo "$nodes_result" | grep -q "ERROR"; then
        warning_output "Node names could not be determined. Try: bash $utils_dir/$get_nodes_list_script -nt all"
        error_output "Node names could not be determined"
    fi

    echo "$nodes_result"
}

# Function to check connection to a node
check_ssh_connectivity() {
    local node_pair=$1
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"

    if test_ssh_connection "$node_name" "$node_ip" "10" "$SSH_USER" "$KEY_PATH" > /dev/null 2>&1; then
        echo -e "  ${green}✓ SSH connection successful${normal}"
        return 0
    else
        echo -e "  ${red}✗ SSH connection failed${normal}"
        return 1
    fi
}

# Check hypervisor
check_hv() {
    echo "Check hypervisors..."

    if [ -z "$HYPERVISOR_HOSTNAME" ]; then
        echo "Hypervisor is not defined. VMs will be created on different hypervisors"
        host=""
        return 0
    fi

    echo "Check Hypervisor: $HYPERVISOR_HOSTNAME..."

    local hypervisor_pair=$(get_nodes_list -nn "$HYPERVISOR_HOSTNAME")

    if [ -z "$hypervisor_pair" ]; then
        error_output "Hypervisor $HYPERVISOR_HOSTNAME not found"
    fi

    if check_ssh_connectivity "$hypervisor_pair"; then
       echo -e "${green}Connection to $HYPERVISOR_HOSTNAME - success${normal}"
    else
        warning_output "No connection to $HYPERVISOR_HOSTNAME"
        error_output "The node $HYPERVISOR_HOSTNAME may be powered off or SSH not accessible"
    fi

    echo "Check nova state on hypervisor: $HYPERVISOR_HOSTNAME..."
    nova_state_list=$(openstack compute service list)
    compute_state=$(echo "$nova_state_list" | grep -E "nova-comput(.)+$HYPERVISOR_HOSTNAME")

    echo "$compute_state" | \
        sed --unbuffered \
            -e 's/\(.*enabled\s\+|\s\+up.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'

    hv_fail_state=$(echo "$compute_state" | grep -E "($HYPERVISOR_HOSTNAME(.)+(disabled|down))|(Internal Server Error \(HTTP 500\))")
    if [ -n "$hv_fail_state" ]; then
        error_output "Nova state fail on $HYPERVISOR_HOSTNAME"
    else
       echo -e "${green}Nova state on $HYPERVISOR_HOSTNAME - OK!${normal}"
    fi
}

# Check project
check_project () {
    echo "Check for exist project: \"$PROJECT\""
    ADMIN_PROJECT_ID=$(openstack project list| grep -E -m 1 "\sadmin\s"| awk '{print $2}')
    if [ -z "$ADMIN_PROJECT_ID" ]; then
        error_output "Impossible to determine the project id admin"
    fi
    PROJ_ID=$(openstack project list| grep -E -m 1 "\s$PROJECT\s"| awk '{print $2}')
    if [ -z "$PROJ_ID" ]; then
        warning_output "Project \"$PROJECT\" does not exist${normal}"
        [[ ! $DONT_ASK = "true" ]] && {
            echo "Create a Project with name: \"$PROJECT\"?";
            read -p "Press enter to continue: ";
            }
        echo "Creating project: \"$PROJECT\"..."
        openstack project create $PROJECT
    else
       echo -e "${green}Project: \"$PROJECT\" exist${normal}"
    fi
    echo "Check for user: \"$TEST_USER\" exist"
    USER_EXIST=$(openstack user list| grep -E " $TEST_USER "| awk '{print $4}')
    if [ -z $USER_EXIST ]; then
        warning_output "User: \"$TEST_USER\" does not exist${normal}"
        [[ ! $DONT_ASK = "true" ]] && {
            echo "Create a user with name: \"$TEST_USER\"?";
            read -p "Press enter to continue: ";
            }
        openstack user create --password $OS_PASSWORD $TEST_USER
    else
       echo -e "${green}User: \"$TEST_USER\" exist${normal}"
    fi
    echo "Check for role assignment: \"$ROLE\" for user: \"$TEST_USER\" in project: \"$PROJECT\""
    ROLE_IN_PROJECT=$(openstack role assignment list --user $TEST_USER --project $PROJECT --names|grep -E "$ROLE(.)+$TEST_USER(.)+$PROJECT")
    if [[ -z $ROLE_IN_PROJECT ]]; then
        warning_output "Role: \"$ROLE\" is not assigned to user: \"$TEST_USER\" in project: \"$PROJECT\"${normal}"
        [[ ! $DONT_ASK = "true" ]] && {
            echo "Assign the role: \"$ROLE\" to user: \"$TEST_USER\" in project: \"$PROJECT\"?";
            read -p "Press enter to continue: ";
            }
        echo "Assign role: \"$ROLE\" to user: \"$TEST_USER\" in project \"$PROJECT\" ..."
        openstack role add --project $PROJECT --user $TEST_USER $ROLE
        openstack role add --project $PROJECT --user admin admin
    else
       echo -e "${green}Role: \"$ROLE\" exist in project: \"$PROJECT\"${normal}"
    fi
    [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] PROJ_ID: $PROJ_ID, PROJECT: $PROJECT"
    unset OS_PROJECT_NAME
    unset OS_PROJECT_ID
    export OS_PROJECT_NAME=$PROJECT
    export OS_PROJECT_ID=$PROJ_ID
    export OS_USERNAME=$TEST_USER
}

# Check and add security group
check_security_group () {
    echo "Check for exist security group: \"$SECURITY_GR\""
    if [ -z "$PROJ_ID" ]; then
        check_project
    fi
    SECURITY_GR_ID=$(openstack security group list|grep -E "($SECURITY_GR(.)*$PROJ_ID)" | head -1 | awk '{print $2}')
    if [ -z "$SECURITY_GR_ID" ]; then
        warning_output "Security group \"$SECURITY_GR\" not found in project \"$PROJECT\"${normal}"
        [[ ! $DONT_ASK = "true" ]] && {
            echo "Create a Security group with a name: \"$SECURITY_GR\"?";
            read -p "Press enter to continue: ";
            }
        echo "Creating security group \"$SECURITY_GR\" in project \"$PROJECT\"..."
        SECURITY_GR_ID=$(openstack security group create --project $PROJECT $SECURITY_GR|grep "id"| head -1 | awk '{print $4}')
        if [ $? -ne 0 ] || [ -z "$SECURITY_GR_ID" ]; then
            error_output "Failed to create security group: $SECURITY_GR"
        fi
        echo "Security group \"$SECURITY_GR\": $SECURITY_GR_ID was created in project \"$PROJECT\""
        echo "Creating rules for \"$SECURITY_GR\" security group...";
        openstack security group rule create --egress --ethertype IPv4 --protocol tcp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol tcp $SECURITY_GR_ID
        openstack security group rule create --egress --ethertype IPv4 --protocol udp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol udp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol icmp $SECURITY_GR_ID
    else
       echo -e "${green}Security group \"$SECURITY_GR\": $SECURITY_GR_ID already exist in project \"$PROJECT\"${normal}"
    fi
}

# Check and add keypair
check_keypair () {
    if [ ! $NO_KEY = "false" ]; then
        key_string=""
    else
        echo "Check for exist keypair: \"$KEY_NAME\""
        KEY_NAME_EXIST=$(openstack keypair list | grep -E "\s$KEY_NAME\s"| awk '{print $2}')
        if [ -z "$KEY_NAME_EXIST" ]; then
            warning_output "Keypair \"$KEY_NAME\" not found in project \"$PROJECT\"${normal}"
            [[ ! $DONT_ASK = "true" ]] && {
                echo "Create a key pair with a name: \"$KEY_NAME\"?";
                read -p "Press enter to continue: ";
                }
            echo "Creating \"$KEY_NAME\" in project \"$PROJECT\"..."
            touch $script_dir/$KEY_NAME.pem
            openstack keypair create $KEY_NAME --public-key $script_dir/"$KEY_NAME".pub
            if [ $? -ne 0 ]; then
                error_output "Failed to create keypair: $KEY_NAME"
            fi
            chmod 400 $script_dir/$KEY_NAME.pem
            echo "Keypair \"$KEY_NAME\" was created in project \"$PROJECT\""
        else
           echo -e "${green}Keypair \"$KEY_NAME\" already exist in project \"$PROJECT\"${normal}"
        fi
        key_string="--key-name $KEY_NAME"
    fi
}

# Check network
check_network () {
    echo "Check for exist network: \"$NETWORK\""
    NETWORK_NAME_EXIST=$(openstack network list| grep "$NETWORK"| awk '{print $2}')
    if [ -z "$NETWORK_NAME_EXIST" ]; then
        warning_output "Network \"$NETWORK\" not found in project \"$PROJECT\"${normal}"
        if [ "$NETWORK" = "pub_net" ]; then
            if yes_no_answer "Do you want to try to create ${NETWORK}?" "Yes"; then
                bash $utils_dir/$create_pub_network_script
            else
                error_output "Network $NETWORK does not exist"
            fi
        else
            warning_output "The script can only create a 'pub_net' network"
            error_output "Network $NETWORK does not exist"
        fi
    else
       echo -e "${green}Network \"$NETWORK\" already exist in project \"$PROJECT\"${normal}"
    fi
}

# Check if image exists in OpenStack and return ID:Name
image_exists_in_openstack() {
    openstack image list | awk -v image="$1" '$4 ~ image {print $2 ":" $4; exit}'
}

# Check image
check_image() {
    echo "Check for exist image: \"$IMAGE\""
    local image_info=$(image_exists_in_openstack "$IMAGE")
    local image_id image_name

    if [ -n "$image_info" ]; then
        image_id=$(awk -F: '{print $1}' <<< "$image_info")
        image_name=$(awk -F: '{print $2}' <<< "$image_info")
    fi

    [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] IMAGE: $IMAGE, image_id: $image_id, image_name: $image_name"

    is_cirros_or_ubuntu=$(echo "$IMAGE" | grep -E "ubuntu|$UBUNTU_IMAGE_NAME|cirros|$CIRROS_IMAGE_NAME")
    is_cirros=$(echo "$IMAGE" | grep -E "cirros|$CIRROS_IMAGE_NAME")
    is_ubuntu=$(echo "$IMAGE" | grep -E "ubuntu|$UBUNTU_IMAGE_NAME")

    [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] is_cirros_or_ubuntu: $is_cirros_or_ubuntu, is_cirros: $is_cirros, is_ubuntu: $is_ubuntu"

    if [ -z "$image_id" ] && [ -z "$is_cirros_or_ubuntu" ]; then
        error_output "Image \"$IMAGE\" not found in project \"$PROJECT\""
    elif [ -z "$image_id" ] && [ -n "$is_ubuntu" ]; then
        warning_output "Image \"$IMAGE\" not found in project \"$PROJECT\""
        local ubuntu_info=$(image_exists_in_openstack "$UBUNTU_IMAGE_NAME")
        local ubuntu_id ubuntu_name
        if [ -n "$ubuntu_info" ]; then
            ubuntu_id=$(awk -F: '{print $1}' <<< "$ubuntu_info")
            ubuntu_name=$(awk -F: '{print $2}' <<< "$ubuntu_info")
        fi
        if [ -z "$ubuntu_id" ]; then
            create_image "$UBUNTU_IMAGE_NAME"
        else
            echo "But image: $ubuntu_name exists in project: $PROJECT"
            [[ ! $DONT_ASK = "true" ]] && read -p "Press enter to use this image and continue: "
            IMAGE="$ubuntu_name"
        fi
    elif [ -z "$image_id" ] && [ -n "$is_cirros" ]; then
        warning_output "Image \"$IMAGE\" not found in project \"$PROJECT\""
        local cirros_info=$(image_exists_in_openstack "$CIRROS_IMAGE_NAME")
        local cirros_id cirros_name
        if [ -n "$cirros_info" ]; then
            cirros_id=$(awk -F: '{print $1}' <<< "$cirros_info")
            cirros_name=$(awk -F: '{print $2}' <<< "$cirros_info")
        fi
        if [ -z "$cirros_id" ]; then
            create_image "$CIRROS_IMAGE_NAME"
        else
            echo "But image: $cirros_name exists in project: $PROJECT"
            [[ ! $DONT_ASK = "true" ]] && read -p "Press enter to use this image and continue: "
            IMAGE="$cirros_name"
        fi
    else
        echo -e "${green}Image \"$image_name\" (ID: $image_id) already exists in project \"$PROJECT\"${normal}"
        IMAGE="$image_id"
    fi
}

# Create image
create_image () {
    if [[ $DONT_ASK = "true" ]] || yes_no_answer "Try to download image: \"$1\" and add to openstack?" "Yes"; then
        bash $utils_dir/$create_image_script_script $1
    fi
}

# Determine flavor name for search and creation
get_flavor_name() {
    local base_flavor="$1:$FLAVOR"
    local project="$2:$PROJECT"

    if [[ "$base_flavor" =~ ^[0-9]+c-[0-9]+r$ ]]; then
        echo "${base_flavor}_${project}"
    else
        echo "$base_flavor"
    fi
}

# Create new flavor
create_flavor() {
    local flavor_name="$1"
    local base_flavor="$2"

    # Parse CPU and RAM from base flavor name
    CPU_DRAFT=$(echo "${base_flavor%-*}")
    RAM_DRAFT=$(echo "${base_flavor##*-}")
    CPU_QTY=$(echo "${CPU_DRAFT%c*}")
    RAM_GB=$(echo "${RAM_DRAFT%r*}")

    if [[ -z $CPU_QTY || -z $RAM_GB ]]; then
        warning_output "The flavor name format should be: <CPUs>c-<RAM GB>r instead: \"$base_flavor\""
        error_output "Can't create a flavor by name: \"$base_flavor\""
    fi

    let "RAM_MB = ${RAM_GB} * 1024"

    [[ ! $DONT_ASK = "true" ]] && {
        echo "Create a flavor with cpus: $CPU_QTY and ram: $RAM_MB Mb: \"$flavor_name\"?";
        read -p "Press enter to continue: ";
    }

    echo "Creating flavor \"$flavor_name\" with $CPU_QTY cpus and $RAM_MB Mb...";
    openstack flavor create --public --vcpus $CPU_QTY --ram $RAM_MB --disk 0 "$flavor_name"
    if [ $? -ne 0 ]; then
        error_output "Failed to create flavor: $flavor_name"
    fi
}

# Check and add flavor
check_flavor() {
    echo "Check for exist flavor: \"$FLAVOR\""

    # Determine flavor name to search for
    local flavor_to_search=$(get_flavor_name "$FLAVOR" "$PROJECT")

    FLAVOR_EXST=$(openstack flavor list | grep -w "$flavor_to_search" | head -n 1 | awk '{print $4}')

    if [ -z "$FLAVOR_EXST" ]; then
        warning_output "Flavor \"$flavor_to_search\" not found in project \"$PROJECT\"${normal}"
        create_flavor "$flavor_to_search" "$FLAVOR"
        NEW_FLAVOR_CREATED="true"
    else
       echo -e "${green}Flavor \"$flavor_to_search\" already exist${normal}"
    fi
}

# Check VMs list
check_vms_list () {
    echo "Check VMs list..."
    openstack server list --all-projects --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks
    echo "Command for check VMs list:"
    warning_output "openstack server list --all-projects --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks${normal}"
}

# Wait for specific VMs to be created by their IDs and names
wait_vms_created () {
    local vm_ids="$1"
    local vm_names="$2"
    local all_active=false
    local attempts=0
    local max_attempts=60

    echo "Waiting for VMs to become active..."

    local id_array=($vm_ids)
    local name_array=($vm_names)
    local total_count=${#id_array[@]}

    while [ $attempts -lt $max_attempts ] && [ "$all_active" = false ]; do
        all_active=true
        active_count=0

        for i in "${!id_array[@]}"; do
            local vm_id="${id_array[i]}"
            local vm_name="${name_array[i]}"

            status=$(openstack server show $vm_id -c status -f value 2>/dev/null)

            if [ "$status" = "ACTIVE" ]; then
                ((active_count++))
                echo -e "${green}✓ $vm_name ($vm_id) is ACTIVE${normal}"
            elif [ "$status" = "ERROR" ]; then
                echo -e "${red}✗ $vm_name ($vm_id) is in ERROR state${normal}"
                all_active=false
            elif [ "$status" = "BUILD" ]; then
                echo -e "${yellow}⏳ $vm_name ($vm_id) is BUILDING${normal}"
                all_active=false
            elif [ -z "$status" ]; then
                echo -e "${yellow}? $vm_name ($vm_id) not found yet${normal}"
                all_active=false
            else
                echo -e "${yellow}? $vm_name ($vm_id) status: $status${normal}"
                all_active=false
            fi
        done

        if [ "$all_active" = true ]; then
            echo -e "${green}All $active_count/$total_count VMs are ACTIVE${normal}"
            break
        else
            echo "Progress: [ attempt: $attempts ] $active_count/$total_count VMs active"
            ((attempts++))
            sleep 5
        fi
    done

    if [ "$all_active" = false ]; then
        echo -e "${red}Timeout reached. Not all VMs became active.${normal}"
        return 1
    fi

    return 0
}

# Create VMs
create_vms () {
    local vm_ids=""
    local vm_names=""
    local vm_info=""

    echo "Creating VMs..."

    FLAVOR_NAME=$(get_flavor_name)
    # Get flavor name
    if [ -z "$FLAVOR_NAME" ]; then
        error_output "Flavor name based on $FLAVOR could not be define"
    fi

    # Get security group ID
    SECURITY_GR_ID=$(get_security_group_id)
    if [ -z "$SECURITY_GR_ID" ]; then
        error_output "Security group $SECURITY_GR not found"
    fi

    # Build key string
    local key_string=""
    if [ "$NO_KEY" = "false" ] && [ -n "$KEY_NAME" ]; then
        key_string="--key-name $KEY_NAME"
    fi

    # Build host string
    local host=""
    if [ -n "$HYPERVISOR_HOSTNAME" ]; then
        host="--hypervisor-hostname $HYPERVISOR_HOSTNAME --os-compute-api-version $API_VERSION"
    fi

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Creation parameters:
        FLAVOR: $FLAVOR_NAME
        SECURITY_GR_ID: $SECURITY_GR_ID
        KEY_STRING: $key_string
        HOST: $host
        ADD_KEY: $ADD_KEY
    "

    for i in $(seq $VM_QTY); do
        if [ "$VM_QTY" = 1 ]; then
            INSTANCE_NAME="${VM_BASE_NAME}"
        else
            INSTANCE_NAME=$(printf "$VM_BASE_NAME-%02d" $i)
        fi

#        echo "Creating VM: $INSTANCE_NAME"

        # Create VM and capture output
        VM_CREATE_OUTPUT=$(openstack server create \
            $INSTANCE_NAME \
            --image $IMAGE \
            --flavor $FLAVOR_NAME \
            --security-group $SECURITY_GR_ID \
            $key_string \
            $host \
            --network $NETWORK \
            --boot-from-volume $VOLUME_SIZE \
            $ADD_KEY)

        # Extract VM ID
        VM_ID=$(echo "$VM_CREATE_OUTPUT" | grep -E "\|\s+id\s+\|" | awk '{print $4}')

        if [ -n "$VM_ID" ]; then
            if [ -z "$vm_ids" ]; then
                vm_ids="$VM_ID"
            else
                vm_ids="$vm_ids $VM_ID"
            fi

            if [ -z "$vm_names" ]; then
                vm_names="$INSTANCE_NAME"
            else
                vm_names="$vm_names $INSTANCE_NAME"
            fi

            if [ -z "$vm_info" ]; then
                vm_info="$VM_ID:$INSTANCE_NAME"
            else
                vm_info="$vm_info $VM_ID:$INSTANCE_NAME"
            fi
            echo -e "Creating VM: $INSTANCE_NAME with ID: $VM_ID ..."
        else
            echo -e "${red}Failed to extract VM ID for $INSTANCE_NAME${normal}"
            echo "VM creation output:"
            echo "$VM_CREATE_OUTPUT"
        fi

        # Timeout between VM creations
        if [ "$BATCH" != "true" ] && [ $i -ne $VM_QTY ]; then
            echo "Next VM will start creating after $TIMEOUT_BEFORE_NEXT_CREATION..."
            sleep $TIMEOUT_BEFORE_NEXT_CREATION
        fi
    done

    # Update cleanup state
    if [ -n "$vm_ids" ]; then
        local next_batch=$(get_next_batch_number)

        # We pass both IDs and names
        if update_cleanup_state "$next_batch" "$vm_ids"; then
#            echo -e "${green}Cleanup state saved for batch $next_batch${normal}"
            if [ "$TS_DEBUG" = "true" ]; then
                echo "[DEBUG] VM info pairs: $vm_info"
            fi
        else
            echo -e "${yellow}Cleanup state not updated${normal}"
        fi

        # We are waiting for VM creation, passing both IDs and names
        if [ "$WAIT_FOR_CREATED" = true ]; then
            wait_vms_created "$vm_ids" "$vm_names"
        fi

    else
        echo -e "${red}No VMs were created successfully${normal}"
        return 1
    fi

    # Show final VMs list
    check_vms_list

    return 0
}

# Function for loading external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            error_output "Error: Required script not found: $script_path"
        fi
        source "$script_path"
    done
}


# Main execution flow
main() {
    use_env_file "$@"

    parse_arguments "$@"
    load_external_scripts
    assign_vars_from_startup_keys
    output_of_initial_parameters

    # Initialize state files
    write_config_file
    init_cleanup_state_file

    # Check OpenStack CLI
    if [[ $CHECK_OPENSTACK = "true" ]]; then
        check_openstack_cli
    fi

    check_and_source_openrc_file

    # Resource checks and creation
    [[ ! $DONT_CHECK = "true" ]] && {
        check_hv
        check_project
        check_network
        check_security_group
        check_image
        check_flavor
        check_keypair
    }


    create_vms

    # Restore admin context
    export OS_PROJECT_NAME='admin'
    export OS_PROJECT_ID=$ADMIN_PROJECT_ID

    echo -e "${green}Cleanup state saved to: $VIRTUAL_ENV/$cleanup_file${normal}"
}

# Run main function
main "$@"
