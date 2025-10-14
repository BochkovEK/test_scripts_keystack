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

# Script configuration
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

# Function: display_help
display_help() {
  cat << EOF

The script outputs Consul logs from $CONSUL_LOG_DIR/$CONSUL_LOG_FILE_NAME on control nodes

Options:
  -ln,  -line_numbers       <log_last_lines_number>  Number of log lines to display
  -n,   -node_name          <node_name>              Specific node to check
  -v,   -debug                                       Enable debug output
  -all, -all_ctrl                                    Check logs on all control nodes
  -u,   -user               <user>                   Set user for SSH access
  --help                                            Display this help message

Examples:
  $0 -n node-01                 # Show logs from specific node
  $0 -all                       # Show logs from all control nodes
  $0 -ln 100                    # Show 100 lines only

EOF
}

# Parse command line arguments
parse_arguments() {
    local count=1
    while [ -n "$1" ]; do
        case "$1" in
            --help)
                display_help
                exit 0
                ;;
            -ln|-line_numbers)
                LOG_LAST_LINES_NUMBER="$2"
                echo "Found -line_numbers with value: $LOG_LAST_LINES_NUMBER"
                shift
                ;;
            -n|-node_name)
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
                ;;
            --)
                shift
                break
                ;;
            *)
              echo "Parameter #$count: $1"
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
    local node_pair="$1"
    local use_follow="${2:-false}"
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"

    local tail_options="-n ${LOG_LAST_LINES_NUMBER}"

    if [ "$use_follow" = "follow" ]; then
        tail_options="-f -n ${LOG_LAST_LINES_NUMBER}"
    fi

    echo -e "${violet}View full log: ssh -t $SSH_USER@$node_ip sudo less $CONSUL_LOG_DIR/$CONSUL_LOG_FILE_NAME${normal}"

    echo "node_ip: $node_ip"

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
    for node_info in $NODES; do
        local node_name="${node_info%%:*}"
        echo -e "${blue}Checking $LOG_LAST_LINES_NUMBER line from consul logs on $node_name...${normal}"
        read_logs "$node_info"
        echo "----------------------------------------"
    done
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

# Function to find consul leader node
find_leader() {
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
            leader_ctrl=$(find_leader "$NODES")
            if [ -z "$leader_ctrl" ]; then
                echo -e "${yellow}Leader node could not be identified${normal}"
                echo -e "${yellow}Falling back to reading logs from all nodes${normal}"
                check_logs_from_all_ctrl "$NODES"
            else
                echo -e "${green}Leader node identified: $leader_ctrl${normal}"
                read_logs "$leader_ctrl" "follow"
            fi
            ;;
    esac

    echo -e "${blue}Script execution completed at: $(date)${normal}"
}

main "$@"