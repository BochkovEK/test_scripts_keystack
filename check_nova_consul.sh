#!/bin/bash

# Script to check service nova, consul, and access to region nodes
# identify nodes with disabled nova services and attempt to enable them
# Can accept path to openrc file as parameter (./check_nova_consul.sh /path/to/openrc)

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
openstack_utils="$utils_dir/openstack"
yes_no_script="$utils_dir/yes_no_answer.sh"
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
get_nodes_list_script="get_nodes_list.sh"
edit_ha_region_config_script="edit_ha_config.sh"
default_ssh_user="root"

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Default values
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $TRY_TO_RISE ]] && TRY_TO_RISE="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $REGION ]] && REGION="region-ps"
[[ -z $CHECK_IPMI ]] && CHECK_IPMI="true"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS] [CHECK_TYPE]

    Options:
      -o, -openrc <path>          Path to openrc file
      -r, -region <name>          Region name
      -dtr, -dont_try_to_rise     Don't attempt to rise disabled nova services
      -u, -user <username>        SSH username
      -ipmi                       Enable IPMI connection checks
      -v, -debug                  Enable debug output
      --help                      Show this help message

    Check types:
      nova    - Check nova state and try to raise disabled hosts
      ipmi    - Check IPMI connections from controllers to computes
    "
}

# Function to define parameters from positional arguments
define_parameters() {
    [ "$TS_DEBUG" = true ] && echo "[DEBUG] Parameter: $1"
    [ "$count" = 1 ] && [[ -n $1 ]] && {
        CHECK="$1"
        echo "Check parameter found with value: $CHECK"
    }
}

# Parse command line arguments
count=1
while [ -n "$1" ]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;

        -o|-openrc)
            OPENRC_PATH="$2"
            echo "Found -openrc option with value: $OPENRC_PATH"
            shift
            ;;

        -r|-region)
            REGION="$2"
            echo "Found -region option with value: $REGION"
            shift
            ;;

        -dtr|-dont_try_to_rise)
            TRY_TO_RISE="false"
            echo "Found -dont_try_to_rise option"
            ;;

        -v|-debug)
            TS_DEBUG="true"
            echo "Found -debug option"
            ;;

        -u|-user)
            SSH_USER="$2"
            echo "Found -user option with value: $SSH_USER"
            shift
            ;;

        -ipmi)
            CHECK_IPMI="true"
            echo "Found -ipmi option"
            ;;

        --)
            shift
            break
            ;;

        *)
            echo "Parameter #$count: $1"
            define_parameters "$1"
            count=$((count + 1))
            ;;
    esac
    shift
done


# Function to check and source openrc file
check_and_source_openrc_file() {
    echo -e "${violet}Checking openrc file...${normal}"
    if bash "$utils_dir/$check_openrc_script" &> /dev/null; then
        openrc_file=$(bash "$utils_dir/$check_openrc_script")
        echo -e "${green}$openrc_file file exists - success${normal}"
        source "$openrc_file"
    else
        bash "$utils_dir/$check_openrc_script"
        echo -e "${red}OpenRC file not found - ERROR${normal}"
        exit 1
    fi
}

# Function to check OpenStack CLI
check_openstack_cli() {
    if [ "$CHECK_OPENSTACK" = "true" ]; then
        if ! bash "$utils_dir/$check_openstack_cli_script"; then
            echo -e "${red}Failed to check OpenStack CLI - ERROR${normal}"
            exit 1
        fi
    fi
}

# Function to check nova service list
check_nova_service_list() {
    echo -e "${violet}Checking nova service list...${normal}"
    echo -e "${yellow}openstack compute service list${normal}"
    nova_state_list=$(openstack compute service list)
    echo "$nova_state_list" | \
        sed --unbuffered \
            -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
}

## Function to get nodes by type using external script
#get_nodes_by_type() {
#    local node_type="$1"
#    local nodes
#
#    case "$node_type" in
#        controls)
#            nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt ctrl)
#            ;;
#        computes)
#            nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt comp)
#            ;;
#        *)
#            echo "Unknown node type: $node_type"
#            return 1
#            ;;
#    esac
#
#    [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] $node_type nodes: $nodes"
#    echo "$nodes"
#}

get_nodes_list() {
    local param_type="$1"
    local param_value="$2"
    local nodes_result=""

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Getting nodes with: $param_type=$param_value"

    if [ "$param_type" = "return_type" ]; then
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" -return_type \"$param_value\"\)"
        nodes_result=$(bash "$utils_dir/$get_nodes_list_script" -return_type "$param_value")
    else
        if [ -n "$param_value" ]; then
            [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$param_type\" \"$param_value\"\)"
            nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$param_type" "$param_value")
        else
            [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$param_type\""
            nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$param_type")
        fi
    fi

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Final NODES list: $nodes_result
    "

    # Check for errors in node list
    if [ -z "$nodes_result" ]; then
        echo -e "${red}Failed to determine node list - ERROR${normal}"
        exit 1
    elif echo "$nodes_result" | grep -q "ERROR"; then
        echo -e "${yellow}Node names could not be determined.${normal}"
        echo -e "${yellow}Try: bash $utils_dir/$get_nodes_list_script -nt all${normal}"
        echo -e "${red}Node names could not be determined - ERROR!${normal}"
        exit 1
    else
        echo "$nodes_result"
    fi
}

# Function to check connection to a node
check_connection_to_node() {
    local node="$1"
    if ping -c 2 "$node" &> /dev/null; then
        echo -e "${green}Connection to $node successful${normal}"
    else
        echo -e "${red}No connection to $node - error!${normal}"
        echo -e "${red}Node may be powered off${normal}\n"
    fi
}

# Function to check connections to nodes of specific type
check_connections_to_nodes() {
    local node_type="$1"
    echo -e "${violet}Checking connections to $node_type nodes...${normal}"

    local node_pair
    node_pair="$(get_nodes_list -nt "$node_type")"

    for host in $node_pair; do
        node_name="${node_pair%%:*}"
        node_ip="${node_pair#*:}"
        check_connection_to_node "$node_ip"
    done
}

# Function to check IPMI connections
check_ipmi_connections() {
    echo -e "${violet}Checking IPMI connections from controllers to computes${normal}"

    [ -z "$nova_state_list" ] && nova_state_list=$(openstack compute service list)

    # Get nodes using external script
    local ctrl_nodes comp_nodes
    ctrl_nodes="$(get_nodes_list -nt ctrl)"
    comp_nodes="$(get_nodes_list -nt comp)"

    local suffix_output suffix
    suffix_output=$(bash "$script_dir/$edit_ha_region_config_script" -u "$SSH_USER")
    suffix=$(echo "$suffix_output" | tail -n1)
    echo "BMC_SUFFIX: $suffix"

    for ctrl_host in $ctrl_nodes; do
        echo "Checking connections from $ctrl_host"
        for comp_host in $comp_nodes; do
            sleep 1
            if ssh "$ctrl_host" ping -c 2 "${comp_host}${suffix}" &> /dev/null; then
                echo -e "${green}Connection to ${comp_host}${suffix} successful${normal}"
            else
                echo -e "${red}No connection to ${comp_host}${suffix} - error!${normal}"
            fi
        done
    done
}

# Function to handle yes/no questions using external script
yes_no_answer() {
    local question="$1"
    local default_answer="${2:-"Yes"}"

    # Export variables for external script
    export TS_YES_NO_QUESTION="$question"
    export TS_DEBUG="$TS_DEBUG"

    # Call external script and capture result
    local result
    result=$(bash "$yes_no_script" "$question" "$default_answer")
    echo "$result"
}

# Function to check and handle disabled compute nodes
check_disabled_computes() {
    echo -e "${violet}Checking for disabled compute nodes...${normal}"
    local cmpt_disabled_nova_list
    cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')

    if [ -n "$cmpt_disabled_nova_list" ]; then
        if [ "$TRY_TO_RISE" = "true" ]; then
            local try_to_rise="false"

            for cmpt in $cmpt_disabled_nova_list; do
                local response
                response=$(yes_no_answer "Do you want to try to enable nova service on $cmpt? [Yes]: ")

                if [ "$response" = "true" ]; then
                    try_to_rise="true"
                    export CHECK_OPENSTACK="false"
                    export COMP_NODE_NAME="$cmpt"
                    export CHECK_AFTER="false"

                    if [ -f "$openstack_utils/try_to_rise_node.sh" ]; then
                        bash "$openstack_utils/try_to_rise_node.sh"
                    else
                        echo -e "${yellow}try_to_rise_node.sh script not found${normal}"
                    fi
                fi
            done

            if [ "$try_to_rise" = "true" ]; then
                check_nova_service_list
            fi
        fi
    fi
}

# Function to check Docker containers
check_docker_containers() {
    local node_type="$1"
    local container_name="$2"

    # Check if external script exists
    if [ ! -f "$script_dir/check_docker_container_state_on_nodes.sh" ]; then
        echo -e "${red}ERROR: Container check script not found${normal}"
        return 1
    fi

    local nodes
    nodes="$(get_nodes_list -nt "$node_type")"

    for host in $nodes; do
        local node_name="${host%%:*}"

        # Execute external script and check for errors
        if ! bash "$script_dir/check_docker_container_state_on_nodes.sh" \
            -nn "$node_name" \
            -u "$SSH_USER" \
            -de "docker" 2>/dev/null | grep "$container_name" | grep -q -E "(unhealthy|restarting|Exited)"; then

            # If grep didn't find error states, check if container exists at all
            if ! bash "$script_dir/check_docker_container_state_on_nodes.sh" \
                -nn "$node_name" \
                -u "$SSH_USER" 2>/dev/null | grep -q "$container_name"; then

                echo -e "${red}ERROR: Container $container_name not found on $node_name${normal}"
            fi
        else
            echo -e "${red}ERROR: Container $container_name has issues on $node_name${normal}"
        fi
    done
}

# Function to check consul members list
check_consul_members() {
    echo -e "${violet}Checking consul members list...${normal}"

    local ctrl_nodes
    ctrl_nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt ctrl)
    local first_ctrl_node
    first_ctrl_node=$(echo "$ctrl_nodes" | head -n1)

    if [ -n "$first_ctrl_node" ]; then
        local members_list
        members_list=$(ssh -t -o StrictHostKeyChecking=no "$first_ctrl_node" "docker exec -it consul consul members list" 2>/dev/null)

        if [ -n "$members_list" ]; then
            echo "$members_list" | \
                sed --unbuffered \
                    -e 's/\(.*alive.*\)/\o033[92m\1\o033[39m/' \
                    -e 's/\(.*failed.*\)/\o033[31m\1\o033[39m/'
        else
            echo -e "${red}Failed to get consul members list${normal}"
        fi
    fi
}

# Function to check consul logs
check_consul_logs() {
    echo -e "${violet}Checking consul logs...${normal}"

    local ctrl_nodes
    ctrl_nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt ctrl)
    local first_ctrl_node
    first_ctrl_node=$(echo "$ctrl_nodes" | head -n1)

    if [ -n "$first_ctrl_node" ]; then
        local leader_node
        leader_node=$(ssh -t -o StrictHostKeyChecking=no "$first_ctrl_node" "docker exec -it consul consul operator raft list-peers" 2>/dev/null | grep leader | awk '{print $1}')

        if [ -n "$leader_node" ]; then
            echo "Leader consul node is $leader_node"
            echo -e "${yellow}ssh -o StrictHostKeyChecking=no $leader_node less /var/log/kolla/autoevacuate.log${normal}"

            ssh -o StrictHostKeyChecking=no "$leader_node" "tail -15 /var/log/kolla/autoevacuate.log 2>/dev/null" | \
                sed --unbuffered \
                    -e 's/\(.*Force off.*\)/\o033[31m\1\o033[39m/' \
                    -e 's/\(.*Server.*\)/\o033[33m\1\o033[39m/' \
                    -e 's/\(.*Evacuating instance.*\)/\o033[33m\1\o033[39m/' \
                    -e 's/\(.*Starting fence.*\)/\o033[31m\1\o033[39m/' \
                    -e 's/\(.*IPMI "power off".*\)/\o033[31m\1\o033[39m/' \
                    -e 's/\(.*disabled,.*\)/\o033[33m\1\o033[39m/' \
                    -e 's/\(.*state: down.*\)/\o033[33m\1\o033[39m/' \
                    -e 's/\(.*CRITICAL.*\)/\o033[31m\1\o033[39m/' \
                    -e 's/\(.*WARNING.*\)/\o033[33m\1\o033[39m/'
        fi
    fi
}

# Function to check consul configuration
check_consul_config() {
    echo -e "${violet}Checking consul configuration...${normal}"

    local ctrl_nodes
    ctrl_nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt ctrl)
    local first_ctrl_node
    first_ctrl_node=$(echo "$ctrl_nodes" | head -n1)

    if [ -n "$first_ctrl_node" ]; then
        local config_path
        config_path=$(bash "$script_dir/$edit_ha_region_config_script" config_path 2>/dev/null | tail -n1)

        if [ -n "$config_path" ]; then
            echo -e "${ORANGE}ssh -t -o StrictHostKeyChecking=no $first_ctrl_node cat $config_path${NC}"

            local config_content
            config_content=$(ssh -o StrictHostKeyChecking=no "$first_ctrl_node" "cat $config_path 2>/dev/null")

            if [ -n "$config_content" ]; then
                echo "Fencing configuration:"
                echo "$config_content" | grep -E '"bmc": \w|"ipmi": \w|alive_compute_threshold|dead_compute_threshold|ceph =|nova =|bmc =|"ceph": \w|"nova": \w|"power_fence_mode"' | \
                    sed --unbuffered \
                        -e 's/\(.*true.*\)/\o033[92m\1\o033[39m/' \
                        -e 's/\(.*True.*\)/\o033[92m\1\o033[39m/' \
                        -e 's/\(.*false.*\)/\o033[31m\1\o033[39m/' \
                        -e 's/\(.*False.*\)/\o033[31m\1\o033[39m/' \
                        -e 's/\(.*alive_compute_threshold.*\)/\o033[33m\1\o033[39m/' \
                        -e 's/\(.*dead_compute_threshold.*\)/\o033[33m\1\o033[39m/'
            else
                echo -e "${red}Failed to read consul configuration${normal}"
            fi
        fi
    fi
}

# Main execution

# Determine SSH user
if [[ -z "$SSH_USER" ]]; then
    SSH_USER=$(whoami 2>/dev/null) || {
        echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
        SSH_USER="$default_ssh_user"
    }
fi

# Validate SSH user
if [[ -z "$SSH_USER" ]]; then
    echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
    exit 1
fi

# Execute checks
check_openstack_cli
check_and_source_openrc_file
check_nova_service_list

# Handle specific check types
case "$CHECK" in
    nova)
        echo "Performing nova checks..."
        check_nova_service_list
        check_disabled_computes
        exit 0
        ;;
    ipmi)
        check_ipmi_connections
        exit 0
        ;;
esac

# Perform comprehensive checks
check_connections_to_nodes "ctrl"
check_connections_to_nodes "comp"

[ "$CHECK_IPMI" = "true" ] && check_ipmi_connections

check_docker_containers "controls" "consul"
check_docker_containers "computes" "consul"
check_docker_containers "computes" "nova_compute"

check_disabled_computes
check_consul_members
check_consul_logs
check_consul_config