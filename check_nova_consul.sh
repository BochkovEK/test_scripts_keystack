#!/bin/bash

# Script to check service nova, consul, and access to region nodes
# identify nodes with disabled nova services and attempt to enable them
# Can accept path to openrc file as parameter (./check_nova_consul.sh /path/to/openrc)

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
openstack_utils="$utils_dir/openstack"
yes_no_script="$utils_dir/yes_no_answer.sh"
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
yes_no_answer_script="yes_no_answer.sh"
edit_ha_config_script="edit_ha_config.sh"
check_consul_log_script="check_consul_log.sh"
try_to_rise_compute_node_script="try_to_rise_compute_node.sh"
check_container_state_on_nodes_script="check_container_state_on_nodes.sh"
default_ssh_user="root"
default_container_engine="docker"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
    "$utils_dir/$yes_no_answer_script"
)

# Default values
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $TRY_TO_RISE ]] && TRY_TO_RISE="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE=$default_container_engine
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"

# Check list
[[ -z $CHECK_CONNECTIONS ]] && CHECK_CONNECTIONS="false"
[[ -z $CHECK_IPMI_CONNECTIONS ]] && CHECK_IPMI_CONNECTIONS="false"
[[ -z $CHECK_DISABLED_COMPUTES ]] && CHECK_DISABLED_COMPUTES="false"
[[ -z $CHECK_CONTAINERS ]] && CHECK_CONTAINERS="false"
[[ -z $CHECK_CONSUL_MEMBERS ]] && CHECK_CONSUL_MEMBERS="false"
[[ -z $CHECK_CONSUL_LOGS ]] && CHECK_CONSUL_LOGS="false"
[[ -z $CHECK_CONSUL_CONFIG ]] && CHECK_CONSUL_CONFIG="false"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS] [CHECK_TYPE]

    Options:
      -o, -openrc <path>                  Path to openrc file
      -r, -region <name>                  Region name
      -dtr, -dont_try_to_rise             Don't attempt to rise disabled nova services
      -u, -user <username>                SSH username
      -ce, -docker_engine <docker\podman> Docker engine
      -v, -debug                          Enable debug output
      --help                              Show this help message

    Individual checks (use instead of CHECK_TYPE):
      -conn, -connections                 Check connections to nodes
      -ipmi_conn                          Check IPMI connections
      -disabled_comp                      Check disabled computes
      -cont, -containers                  Check containers state
      -consul_members                     Check consul members
      -consul_logs                        Check consul logs
      -consul_config                      Check consul configuration

    Check types:
      nova    - Check nova state and try to raise disabled hosts
      ipmi    - Check IPMI connections from controllers to computes
    "
}

# Function to define parameters from positional arguments
define_parameters() {
    [ "$count" = 1 ] && [ "$1" = "suffix" ] && {
        CHECK_SUFFIX=true
        echo "Check suffix parameter found"
    }
    [ "$count" = 1 ] && [ "$1" = "config_path" ] && {
        GET_CONFIG_PATH=true
        echo "Get config path parameter found"
    }
}

# Parse command line arguments
parse_arguments() {
    local count=1
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
            -ce|-container_engine)
                CONTAINER_ENGINE="$2"
                echo "Found -docker_engine option with value: $CONTAINER_ENGINE"
                shift
                ;;
            -conn|-connections)
                CHECK_CONNECTIONS="true"
                echo "Found -connections option"
                ;;
            -ipmi_conn)
                CHECK_IPMI_CONNECTIONS="true"
                echo "Found -ipmi_conn option"
                ;;
            -disabled_comp)
                CHECK_DISABLED_COMPUTES="true"
                echo "Found -disabled_comp option"
                ;;
            -cont|-containers)
                CHECK_CONTAINERS="true"
                echo "Found -containers option"
                ;;
            -consul_members)
                CHECK_CONSUL_MEMBERS="true"
                echo "Found -consul_members option"
                ;;
            -consul_logs)
                CHECK_CONSUL_LOGS="true"
                echo "Found -consul_logs option"
                ;;
            -consul_config)
                CHECK_CONSUL_CONFIG="true"
                echo "Found -consul_config option"
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
}

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

# Function to get nodes list using external script
get_nodes_list() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""
    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result: $nodes_result
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

# Function to check nova service list
check_nova_service_list() {
    echo -e "${violet}Checking nova service list...${normal}"
    echo -e "openstack compute service list"
    nova_state_list=$(openstack compute service list)
    echo "$nova_state_list" | \
        sed --unbuffered \
            -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
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

# Function to check connection to a node
check_connection_to_node() {
    node_pair=$1
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"
    if ping -c 2 "$node_ip" &> /dev/null; then
        echo -e "${green}Connection to $node_name successful${normal}"
    else
        echo -e "${red}No connection to $node_name - error!${normal}"
        echo -e "${red}Node may be powered off${normal}\n"
    fi
}

# Function to check connections to nodes of specific type
check_connections_to_nodes() {
    local node_type="$1"
    echo -e "${violet}Checking connections to $node_type nodes...${normal}"

    local nodes
    if [ "$TS_DEBUG" = true ]; then
      echo "node_type: $node_type"
      get_nodes_list -nt $node_type
    fi
    nodes=$(get_nodes_list -nt $node_type)

    for node_pair in $nodes; do
        check_connection_to_node "$node_pair"
    done
}

# Function to check IPMI connections
check_ipmi_connections() {
    echo -e "${violet}Checking IPMI connections from controllers to computes${normal}"

    # Get nodes using external script
    local ctrl_nodes rmi_nodes
    local suffix_output suffix

    suffix_output=$(bash "$script_dir/$edit_ha_config_script" -u "$SSH_USER" "-suffix")
    suffix=$(echo "$suffix_output" | tail -n1 | sed 's/^-//')
    echo "BMC_SUFFIX: $suffix"

    ctrl_nodes=$(get_nodes_list -nt ctrl)
    rmi_nodes=$(get_nodes_list -nt rmi -suffix "$suffix")

    for ctrl_node_pair in $ctrl_nodes; do
        ctrl_node_name="${ctrl_node_pair%%:*}"
        ctrl_node_ip="${ctrl_node_pair#*:}"
        echo "Checking connections from $ctrl_node_name"
        for rmi_node_pair in $rmi_nodes; do
            rmi_node_name="${rmi_node_pair%%:*}"
            rmi_node_ip="${rmi_node_pair#*:}"
            sleep 1
            if ssh "$SSH_USER@$ctrl_node_ip" ping -c 2 "$rmi_node_ip" &> /dev/null; then
                echo -e "${green}Connection to $rmi_node_name successful${normal}"
            else
                echo -e "${red}No connection to $rmi_node_name - error!${normal}"
            fi
        done
    done
}

# Function to check and handle disabled compute nodes
check_disabled_computes() {
    echo -e "${violet}Checking for disabled compute nodes...${normal}"
    local comp_disabled_nova_list
    comp_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        nova_state_list: $nova_state_list
        comp_disabled_nova_list: $comp_disabled_nova_list
    "

    if [ -n "$comp_disabled_nova_list" ]; then
        local try_to_rise="false"

        for cmpt in $comp_disabled_nova_list; do
            local response
            response=$(yes_no_answer "Do you want to try to enable nova service on $cmpt? [Yes]: ")
            [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        cmpt: $cmpt
        response: $response
    "
            if [ "$response" = "true" ]; then
                try_to_rise="true"
                export CHECK_OPENSTACK="false"
                export COMP_NODE_NAME="$cmpt"
                export CHECK_AFTER="false"
                export SSH_USER=$SSH_USER
                export CONTAINER_ENGINE=$CONTAINER_ENGINE

                [ "$TS_DEBUG" = true ] && echo -e "try check script file $openstack_utils/$try_to_rise_compute_node_script"
                if [ -f "$openstack_utils/$try_to_rise_compute_node_script" ]; then
                    [ "$TS_DEBUG" = true ] && echo -e "$try_to_rise_compute_node_script exists - ok"
                    bash "$openstack_utils/$try_to_rise_compute_node_script"
                else
                    echo -e "${yellow}$try_to_rise_compute_node_script script not found${normal}"
                fi
            fi
        done

        if [ "$try_to_rise" = "true" ]; then
            check_nova_service_list
        fi
    else
        echo -e "${green}The nova-compute service on all compute nodes is in the state 'up' and status 'enabled' - ok${normal}"
    fi
}

# Function to check Docker containers
check_containers() {
    local node_type="$1"
    local container_name="$2"

    echo -e "${violet}Checking $container_name on $node_type...${normal}"

    local nodes
    nodes=$(get_nodes_list -nt "$node_type")

    local node_name
    local nodes_name_list
    if [ -n "$nodes" ]; then
        for pair in $nodes; do
            node_name="${pair%%:*}"
            nodes_name_list="$nodes_name_list $node_name"
        done
    else
        echo -e "${red}ERROR: nodes list type $node_type could not be define${normal}"
        return 1
    fi

    # Check if external script exists
    if [ ! -f "$script_dir/$check_container_state_on_nodes_script" ]; then
        echo -e "${red}ERROR: Container check script not found${normal}"
        return 1
    fi

    bash "$script_dir/$check_container_state_on_nodes_script" \
        -nn "$nodes_name_list" \
        -u "$SSH_USER" \
        -ce "$CONTAINER_ENGINE" 2>/dev/null | grep "$container_name"
}

# Function to check ssl config
check_ssl_config() {
    local ssl_config_output
    [ ! -f "$script_dir/$edit_ha_config_script" ] && {
      echo -e "${yellow}Script $edit_ha_config_script does not exist in $script_dir/${normal}";
      return 1;
      }
    ssl_config_output=$(bash "$script_dir/$edit_ha_config_script" -u "$SSH_USER" "-ssl_check"| tail -n1)
    echo "$ssl_config_output"
    return 0
}

# Function to check consul members list
check_consul_members() {
    echo -e "${violet}Checking consul members list...${normal}"

    local ssl_config_output
    local members_list
    local ctrl_nodes
    local first_ctrl_node_pair

    ctrl_nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt ctrl)
    first_ctrl_node_pair=$(echo "$ctrl_nodes" | awk '{print $1}')

    if [ -n "$first_ctrl_node_pair" ]; then
        local node_name="${first_ctrl_node_pair%%:*}"
        local node_ip="${first_ctrl_node_pair#*:}"
    else
        echo -e "${yellow}Failed to define any ctrl node${normal}"
        return 1
    fi

    if ssl_config_output=$(check_ssl_config); then
        IFS=';' read -r -a parts <<< "$ssl_config_output"

        mode="${parts[0]}"  # "mtls"
        https_ssl_verify=$(echo "${parts[1]}" | awk -F' = ' '{print $2}' | xargs)
        client_key=$(echo "${parts[2]}" | awk -F' = ' '{print $2}' | xargs)
        client_cert=$(echo "${parts[3]}" | awk -F' = ' '{print $2}' | xargs)

        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]
        ssl_config_output: $ssl_config_output
        mode: $mode
        https_ssl_verify: $https_ssl_verify
        client_key: $client_key
        client_cert: $client_cert
        "

        if [ "$mode" = "mtls" ];then
            members_list=$(ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                "sudo $CONTAINER_ENGINE exec consul consul members \
                -http-addr=https://$node_ip:8501 -ca-file $https_ssl_verify \
                -client-cert $client_cert \
                -client-key $client_key 2>/dev/null")
        else
            members_list=$(ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                "sudo $CONTAINER_ENGINE exec -it consul consul members list 2>/dev/null")
        fi

        if [ -n "$members_list" ]; then
            echo "$members_list" | \
                sed --unbuffered \
                    -e 's/\(.*alive.*\)/\o033[92m\1\o033[39m/' \
                    -e 's/\(.*failed.*\)/\o033[31m\1\o033[39m/' \
                    -e 's/\(.*Error.*\)/\o033[31m\1\o033[39m/' \
                    -e 's/\(.*error.*\)/\o033[31m\1\o033[39m/'
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
    local first_ctrl_node_pair
    first_ctrl_node_pair=$(echo "$ctrl_nodes" | awk '{print $1}')

    if [ -n "$first_ctrl_node_pair" ]; then
        local node_name="${first_ctrl_node_pair%%:*}"
        local node_ip="${first_ctrl_node_pair#*:}"
    else
        echo -e "${yellow}Failed to define any ctrl node${normal}"
        return 1
    fi

    if [ ! -f "$script_dir/$check_consul_log_script" ]; then
        echo -e "${yellow}$check_consul_log_script not exists in $script_dir${normal}"
        return 1
    fi

    bash "$script_dir/$check_consul_log_script" -ctrl_list "$node_name"
    return 0
}

# Function to check consul configuration
check_consul_config() {
    echo -e "${violet}Checking consul configuration...${normal}"

    local ctrl_nodes
    ctrl_nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt ctrl)
    local first_ctrl_node_pair
    first_ctrl_node_pair=$(echo "$ctrl_nodes" | awk '{print $1}')

    if [ -n "$first_ctrl_node_pair" ]; then
        local config_path
        local node_name="${first_ctrl_node_pair%%:*}"
        local node_ip="${first_ctrl_node_pair#*:}"
        config_path=$(bash "$script_dir/$edit_ha_config_script" config_path 2>/dev/null | tail -n1)

        if [ -n "$config_path" ]; then
            echo -e "${yellow}ssh -t -o StrictHostKeyChecking=no \"$SSH_USER@$node_ip\" sudo cat $config_path${normal}"

            local config_content
            config_content=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo cat $config_path 2>/dev/null")

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

# Function to load external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            echo -e "${red}Error: Required script not found: $script_path${normal}"
            exit 1
        fi
        source "$script_path"
    done
}

# Main execution function
main() {
    parse_arguments "$@"

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    # Execute checks
    check_openstack_cli
    check_and_source_openrc_file

    any_specific_check="$CHECK_CONNECTIONS$CHECK_IPMI_CONNECTIONS$CHECK_DISABLED_COMPUTES$CHECK_CONTAINERS$CHECK_CONSUL_MEMBERS$CHECK_CONSUL_LOGS$CHECK_CONSUL_CONFIG"

    if [[ "$any_specific_check" == *"true"* ]]; then
        echo "Performing specific checks only..."

        [ "$CHECK_CONNECTIONS" = "true" ] && {
            check_connections_to_nodes "ctrl"
            check_connections_to_nodes "comp"
        }

        # Only if individual check -ipmi_conn use
        [ "$CHECK_IPMI_CONNECTIONS" = "true" ] && check_ipmi_connections

        [ "$CHECK_DISABLED_COMPUTES" = "true" ] && {
            check_nova_service_list
            check_disabled_computes
        }

        [ "$CHECK_CONTAINERS" = "true" ] && {
            check_containers "ctrl" "consul"
            check_containers "comp" "consul"
            check_containers "comp" "nova_compute"
        }

        [ "$CHECK_CONSUL_MEMBERS" = "true" ] && check_consul_members
        [ "$CHECK_CONSUL_LOGS" = "true" ] && check_consul_logs
        [ "$CHECK_CONSUL_CONFIG" = "true" ] && check_consul_config

        exit 0
    fi

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

    # Default checks if no specific options provided
    check_nova_service_list
    check_connections_to_nodes "ctrl"
    check_connections_to_nodes "comp"

    check_containers "ctrl" "consul"
    check_containers "comp" "consul"
    check_containers "comp" "nova_compute"

    check_disabled_computes
    check_consul_members
    check_consul_logs
    check_consul_config
}

# Run main function
main "$@"