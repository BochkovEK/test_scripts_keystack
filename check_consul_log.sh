#!/bin/bash

# Script to display logs from consul service
# Can check logs on specific nodes or automatically detect consul leader

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
default_ssh_user="root"
default_container_engine="docker"

# Colors
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 14)
#violet=$(tput setaf 5)

# Default values
[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=35
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $CTRL_LIST ]] && CTRL_LIST=""
[[ -z $ALL_CTRL ]] && ALL_CTRL="false"
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE=$default_container_engine

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -ln, -line_numbers <number>    Number of log lines to display
      -ctrl_list <nodes>             Space-separated list of controller nodes
      -all_ctrl                      Check logs on all controller nodes
      -u, -user <username>           SSH username
      -de, -docker_engine <engine>   Container engine: docker or podman
      --help                         Show this help message

    Examples:
      bash check_consul_log.sh -ctrl_list \"ctrl-01 ctrl-02\" -ln 50
      bash check_consul_log.sh -all_ctrl
    "
}

# Parse command line arguments
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
            CTRL_LIST="$2"
            echo "Found -ctrl_list with value: $CTRL_LIST"
            shift
            ;;

        -all_ctrl)
            ALL_CTRL="true"
            echo "Found -all_ctrl option"
            ;;

        -u|-user)
            SSH_USER="$2"
            echo "Found -user with value: $SSH_USER"
            shift
            ;;

        -de|-docker_engine)
            CONTAINER_ENGINE="$2"
            echo "Found -docker_engine with value: $CONTAINER_ENGINE"
            shift
            ;;

        --)
            shift
            break
            ;;

        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
    shift
done

# Function to get nodes list using external script
get_nodes_list() {
    local param_type="$1"
    local param_value="$2"

    local nodes
    nodes=$(bash "$utils_dir/$get_nodes_list_script" "-$param_type" "$param_value" 2>/dev/null)

    if [ -z "$nodes" ] || echo "$nodes" | grep -q "ERROR"; then
        echo -e "${red}Failed to get nodes list - ERROR${normal}" >&2
        return 1
    fi

    echo "$nodes"
}

# Function to check consul logs on a single node
check_consul_log_one_node() {
    local node_identifier="$1"

    # Get node details using external script
    local node_info
    node_info=$(get_nodes_list "nn" "$node_identifier")
    [ $? -ne 0 ] && return 1

    local node_name="${node_info%%:*}"
    local node_ip="${node_info#*:}"

    # Determine tail command options
    local tail_options="-n $LOG_LAST_LINES_NUMBER"
    [ "$ALL_CTRL" != "true" ] && tail_options="-f"

    # Display log header
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "echo -e '\033[0;35m$(date)\033[0m
\033[0;35mLogs from: $(hostname)\033[0m
\033[0;35mView full log: ssh $(hostname) less /var/log/kolla/autoevacuate.log\033[0m'"

    # Display colored log output
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo tail $tail_options /var/log/kolla/autoevacuate.log 2>/dev/null" | \
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
check_logs_on_all_ctrl() {
    local ctrl_nodes
    ctrl_nodes=$(get_nodes_list "nt" "ctrl")
    [ $? -ne 0 ] && return 1

    for node_info in $ctrl_nodes; do
        local node_name="${node_info%%:*}"
        echo -e "${cyan}Checking logs on $node_name...${normal}"
        check_consul_log_one_node "$node_name"
        echo "----------------------------------------"
    done
}

# Function to find consul leader node
find_consul_leader() {
    local ctrl_nodes="$1"

    for node_info in $ctrl_nodes; do
        local node_name="${node_info%%:*}"
        local node_ip="${node_info#*:}"

        local leader
        leader=$(ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo $CONTAINER_ENGINE exec consul consul operator raft list-peers 2>/dev/null" | \
            grep leader | awk '{print $1}')

        if [ -n "$leader" ]; then
            echo "$leader"
            return 0
        fi
    done

    echo -e "${yellow}Warning: Consul leader not found${normal}" >&2
    return 1
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

# Get controller nodes list
if [ -z "$CTRL_LIST" ]; then
    CTRL_NODES=$(get_nodes_list "nt" "ctrl")
    [ $? -ne 0 ] && exit 1
else
    CTRL_NODES=$(get_nodes_list "nn" "$CTRL_LIST")
    [ $? -ne 0 ] && exit 1
fi

# Determine which nodes to check
if [ "$ALL_CTRL" = "true" ]; then
    echo -e "${cyan}Checking logs on all controller nodes...${normal}"
    check_logs_on_all_ctrl
else
    # Try to find consul leader
    LEADER_NODE=$(find_consul_leader "$CTRL_NODES")

    if [ -n "$LEADER_NODE" ]; then
        echo -e "${cyan}Found consul leader: $LEADER_NODE${normal}"
        check_consul_log_one_node "$LEADER_NODE"
    else
        echo -e "${yellow}No leader found, checking all controller nodes${normal}"
        ALL_CTRL="true"
        check_logs_on_all_ctrl
    fi
fi