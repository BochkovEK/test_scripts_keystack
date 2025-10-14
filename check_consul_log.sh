#!/bin/bash

# Script to display logs from consul service
# Can check logs on specific nodes or automatically detect consul leader

# Colors
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
blue=$(tput setaf 6)
violet=$(tput setaf 5)

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
edit_ha_config_script="edit_ha_config.sh"
consul_log_dir="/var/log/kolla"
consul_log_file_name="autoevacuate.log"
nodes_type="ctrl"
default_ssh_user="root"
default_container_engine="docker"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
)

# Default values
[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=35
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $CONSUL_LOG_DIR ]] && CONSUL_LOG_DIR=$consul_log_dir
[[ -z $CONSUL_LOG_FILE_NAME ]] && CONSUL_LOG_FILE_NAME=$consul_log_file_name
[[ -z $CTRL_NAME ]] && CTRL_NAME=""
[[ -z $ALL_CTRL ]] && ALL_CTRL="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE=$default_container_engine

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -ln, -line_numbers <number>      Number of log lines to display
      -ctrl_list <nodes>               Space-separated list of controller nodes
      -all, -all_ctrl                  Check logs on all controller nodes
      -u, -user <username>             SSH username
      -ce, -container_engine <engine>  Container engine: docker or podman
      -v, -debug                       Enable debug output
      --help                           Show this help message

    Examples:
      bash check_consul_log.sh -ctrl_list \"ctrl-01 ctrl-02\" -ln 50
      bash check_consul_log.sh -all_ctrl
    "
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
            -ln|-line_numbers)
                LOG_LAST_LINES_NUMBER="$2"
                echo "Found -line_numbers with value: $LOG_LAST_LINES_NUMBER"
                shift
                ;;
            -ctrl_list)
                CTRL_NAME="$2"
                echo "Found -ctrl_list with value: $CTRL_NAME"
                shift
                ;;
            -all|-all_ctrl)
                ALL_CTRL="true"
                echo "Found -all_ctrl option"
                ;;
            -u|-user)
                SSH_USER="$2"
                echo "Found -user with value: $SSH_USER"
                shift
                ;;
            -ce|-container_engine)
                CONTAINER_ENGINE="$2"
                echo "Found -docker_engine with value: $CONTAINER_ENGINE"
                shift
                ;;
            -v|-debug)
                TS_DEBUG="true"
                echo "Found -debug with value: $TS_DEBUG"
                shift
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

# Function to check consul logs on a single node
read_logs() {
    local node_identifier="$1"
    local use_follow="${2:-false}"

    # Get node details using external script
    local node_info
    node_info=$(get_nodes_list "-nn" "$node_identifier")
    [ $? -ne 0 ] && return 1

    local node_name="${node_info%%:*}"
    local node_ip="${node_info#*:}"

    local tail_options="-n ${LOG_LAST_LINES_NUMBER}"

    if [ "$use_follow" = "follow" ]; then
        tail_options="-f -n ${LOG_LAST_LINES_NUMBER}"
    fi

#    # Display log header
#    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
#        "echo -e '\033[0;35m$(date)\033[0m
#\033[0;35mLogs from: $(hostname)\033[0m
#\033[0;35mView full log: ssh $(hostname) less /var/log/kolla/autoevacuate.log\033[0m'"

    echo -e "${violet}View full log: ssh -t $SSH_USER@$node_ip sudo less $CONSUL_LOG_DIR/$CONSUL_LOG_FILE_NAME${normal}"

    # Display colored log output
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo tail $tail_options $CONSUL_LOG_DIR/$CONSUL_LOG_FILE_NAME 2>/dev/null" | \
        sed --unbuffered \
            -e 's/\([1-9][0-9]* computes in maintenance\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*Force off.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*Server.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*Evacuating instance.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*IPMI "power off".*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*CRITICAL.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*ERROR.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*Not enough.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*Too many.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*disabled,.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*failed: True.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*WARNING.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*status_code: 400.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*Starting fence.*\)/\o033[33m\1\o033[39m/'
}

# Function to check logs on all controller nodes
check_logs_from_all_ctrl() {
#    local ctrl_nodes
#    ctrl_nodes=$(get_nodes_list "nt" "ctrl")
#    [ $? -ne 0 ] && return 1

    for node_info in $NODES; do
        local node_name="${node_info%%:*}"
        echo -e "${blue}Checking $LOG_LAST_LINES_NUMBER line from consul logs on $node_name...${normal}"
        read_logs "$node_name"
        echo "----------------------------------------"
    done
}

# Function to check ssl config
check_ssl_config() {
#    echo -e "${cyan}Checking SSL configuration...${normal}"

    local ssl_config_output
    [ ! -f "$script_dir/$edit_ha_config_script" ] && {
      echo -e "${yellow}Script $edit_ha_config_script does not exist in $script_dir/${normal}";
      return 1;
      }
    ssl_config_output=$(bash "$script_dir/$edit_ha_config_script" -u "$SSH_USER" "-ssl_check"| tail -n1)
#    ssl_type=$(echo "$ssl_config_output" )
    echo "$ssl_config_output"
    return 0
}

# Function to find consul leader node
find_leader() {
#    local ctrl_nodes="$1"
    local ssl_config_output

    for node_info in $NODES; do
        local node_name="${node_info%%:*}"
        local node_ip="${node_info#*:}"

        local leader

        if ssl_config_output=$(check_ssl_config); then
            IFS=';' read -r -a parts <<< "$ssl_config_output"

            mode="${parts[0]}"  # "mtls"
            https_ssl_verify=$(echo "${parts[1]}" | awk -F' = ' '{print $2}' | xargs)
            client_key=$(echo "${parts[2]}" | awk -F' = ' '{print $2}' | xargs)
            client_cert=$(echo "${parts[3]}" | awk -F' = ' '{print $2}' | xargs)

            if [ "$mode" = "mtls" ];then
                [ "$TS_DEBUG" = true ] && echo -e "
    leader=\$(ssh -t -o StrictHostKeyChecking=no \"$SSH_USER@$node_ip\" \
                    \"sudo $CONTAINER_ENGINE exec consul consul operator raft list-peers
                     -http-addr=https://$node_ip:8501 -ca-file $https_ssl_verify
                     -client-cert $client_cert
                     -client-key $client_key 2>/dev/null\" | \
                    grep leader | awk '{print \$1}')
                "
                leader=$(ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                    "sudo $CONTAINER_ENGINE exec consul consul operator raft list-peers \
                     -http-addr=https://$node_ip:8501 -ca-file $https_ssl_verify \
                     -client-cert $client_cert \
                     -client-key $client_key 2>/dev/null" | \
                    grep leader | awk '{print $1}')
            else
                leader=$(ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                    "sudo $CONTAINER_ENGINE exec consul consul operator raft list-peers 2>/dev/null" | \
                    grep leader | awk '{print $1}')
            fi
        fi

        if [ -n "$leader" ]; then
            echo "$leader"
            return 0
        fi
    done

    echo -e "${yellow}Warning: Consul leader not found${normal}" >&2
    return 1
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

## Main execution
#main() {
#    # Parse command line arguments
#    parse_arguments "$@"
#
#    # Load external scripts first
#    load_external_scripts
#
#    # Determine SSH user using external function
#    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
#    if [[ $? -ne 0 ]]; then
#        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
#        exit 1
#    fi
#
#    echo -e "Using SSH user: $SSH_USER"
#
#    # Get controller nodes list
#    if [ -z "$CTRL_NAME" ]; then
#        NODES=$(get_nodes_list "-nt" "$nodes_type")
#        [ $? -ne 0 ] && exit 1
#    else
#        NODES=$(get_nodes_list "-nn" "$CTRL_NAME")
#        [ $? -ne 0 ] && exit 1
#    fi
#
#    # Determine which nodes to check
#    if [ "$ALL_CTRL" = "true" ] || [ -n "$CTRL_NAME" ]; then
#        echo -e "${blue}Checking logs on all controller nodes...${normal}"
#        check_logs_on_all_ctrl
#    else
#        # Try to find consul leader
#        LEADER_NODE=$(find_leader)
#
#        if [ -n "$LEADER_NODE" ]; then
#            echo -e "${green}Leader node identified: $LEADER_NODE${normal}"
#            read_logs "$LEADER_NODE"
#        else
#            echo -e "${yellow}No leader found, checking all controller nodes${normal}"
#            ALL_CTRL="true"
#            check_logs_on_all_ctrl
#        fi
#    fi
#}
#
#main "$@"

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Load external scripts first
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    echo -e "Using SSH user: $SSH_USER"

    # Determine operation type and get nodes list
    if [ -n "$CTRL_NAME" ]; then
        OPERATION="specific_node"
        NODES=$(get_nodes_list "-nn" "$CTRL_NAME")
        echo -e "${blue}Reading logs from specific node: $CTRL_NAME${normal}"
    elif [ "$ALL_CTRL" = "true" ]; then
        OPERATION="all_nodes"
        NODES=$(get_nodes_list "-nt" "$nodes_type")
        echo -e "${blue}Checking logs on all controller nodes...${normal}"
    else
        OPERATION="auto_leader"
        NODES=$(get_nodes_list "-nt" "$nodes_type")
#        echo -e "${blue}Attempting to identify DRS leader node automatically${normal}"
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "${blue}Nodes: $NODES${normal}"

    # Execute the determined operation
    case "$OPERATION" in
        "specific_node")
            read_logs "$NODES" "follow"
            ;;
        "all_nodes")
            check_logs_from_all_ctrl "$NODES"
            ;;
        "auto_leader")
            leader_drs_ctrl=$(find_leader "$NODES")
            if [ -z "$leader_drs_ctrl" ]; then
                echo -e "${yellow}Leader node could not be identified${normal}"
                echo -e "${yellow}Falling back to reading logs from all nodes${normal}"
                check_logs_from_all_ctrl "$NODES"
            else
                echo -e "${green}Leader node identified: $leader_drs_ctrl${normal}"
                read_logs "$leader_drs_ctrl" "follow"
            fi
            ;;
    esac

    echo -e "${blue}Script execution completed at: $(date)${normal}"
}

main "$@"