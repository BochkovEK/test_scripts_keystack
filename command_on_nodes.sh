#!/bin/bash

# Script to execute commands on multiple nodes
# Requires node IPs and names to be defined in /etc/hosts

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
yes_no_script="$utils_dir/yes_no_answer.sh"
get_nodes_list_script="get_nodes_list.sh"
default_ssh_user="root"

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

# Default values
[[ -z $COMMAND ]] && COMMAND="ls -la"
[[ -z $NODES ]] && NODES=()
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $PING ]] && PING="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $DONT_CHECK_CONN ]] && DONT_CHECK_CONN="true"
[[ -z $SEND_ENVS ]] && SEND_ENVS=""

# Parameter counter
count=1

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Execute commands on multiple nodes. Node IPs and names must be defined in /etc/hosts.

    Options:
      -c, -command <command>          Command to execute on nodes
      -nt, -type_of_nodes <type>      Node type: 'ctrl', 'comp', 'net', 'all'
      -nn, -node_name <names>         Specific node names (space-separated)
      -u, -user <username>            SSH username
      -p, -ping                       Ping nodes before executing command
      -check_conn                     Check connection before executing commands
      -se, -send_envs                 Send envs like -se \"MY_VARIABLE='value'\"
      -debug                          Enable debug mode
      --help                          Show this help message

    Examples:
      Remove all containers on all nodes:
        bash command_on_nodes.sh -c 'docker stop \$(docker ps -a -q)'
        bash command_on_nodes.sh -c 'docker system prune -af'
        bash command_on_nodes.sh -c 'docker volume prune -af'
    "
}

# Function to define parameters from positional arguments
define_parameters() {
    [ "$count" = 1 ] && [[ -n $1 ]] && {
        COMMAND="$1"
        echo "Command parameter found with value: $COMMAND"
    }
}

# Parse command line arguments
while [ -n "$1" ]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;

        -c|-command)
            COMMAND="$2"
            echo "Found -command option with value: $COMMAND"
            shift
            ;;

        -nt|-type_of_nodes)
            NODES_TYPE="$2"
            echo "Found -type_of_nodes option with value: $NODES_TYPE"
            shift
            ;;

        -u|-user)
            SSH_USER="$2"
            echo "Found -user option with value: $SSH_USER"
            shift
            ;;

        -se|-send_envs)
           SEND_ENVS="$2"
           echo "Found -send_envs option with value: $SEND_ENVS"
           shift
           ;;

        -nn|-node_name)
            NODES_NAME="$2"
            echo "Found -node_name option with value: $NODES_NAME"
            shift
            ;;

        -p|-ping)
            PING="true"
            echo "Found -ping option"
            ;;

        -debug)
            TS_DEBUG="true"
            echo "Found -debug option"
            ;;

        -check_conn)
            DONT_CHECK_CONN="false"
            echo "Found -check_conn option"
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

# Function to display error messages and exit
error_output() {
    echo "${yellow}Command not executed on $NODES_TYPE nodes${normal}"
    echo "${red}$error_message - error${normal}"
    exit 1
}

# Function to check connectivity to nodes
check_connection() {
    for host in "${NODES[@]}"; do
        echo "Checking connection to: $host"
        sleep 1
        if ping -c 2 "$host" &> /dev/null; then
            printf "%40s\n" "${green}Connection to $host successful${normal}"
        else
            printf "%40s\n" "${red}No connection to $host - error!${normal}"
        fi
    done
}

# Function to execute commands on all nodes
start_commands_on_nodes() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Nodes list:"

    for host in "${NODES[@]}"; do
        [ "$TS_DEBUG" = true ] && echo "$host"
    done

    # Validate nodes list
    if [ ${#NODES[@]} -eq 0 ]; then
        error_message="Failed to compile the list of nodes ($NODES_TYPE)"
        error_output
    fi

    # Execute command on each node
    for node_pair in "${NODES[@]}"; do
        # Split node:ip format
        node_name="${node_pair%%:*}"
        node_ip="${node_pair#*:}"
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] node_name: $node_name; node_ip: $node_ip"
        echo -E "${blue}Executing command on ${node_name}${normal}"
        if [ -n "$SEND_ENV" ]; then
            [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Executing command: ssh -o StrictHostKeyChecking=no -t \"$SEND_ENV\" \"$SSH_USER@$node_ip\" \"$COMMAND\""
            ssh -o StrictHostKeyChecking=no -t "$SEND_ENV" "$SSH_USER@$node_ip" "$COMMAND"
        else
            [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Executing command: ssh -o StrictHostKeyChecking=no -t \"$SSH_USER@$node_ip\" \"$COMMAND\""
            ssh -o StrictHostKeyChecking=no -t "$SSH_USER@$node_ip" "$COMMAND"
        fi
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

# Function to check ping connectivity to a node
check_ping() {
    local node_ip="$1"

    if ping -c 2 "$node_ip" &> /dev/null; then
        printf "%40s\n" "${green}Ping to $node_ip successful${normal}"
        sleep 1
    else
        printf "%40s\n" "${red}No ping response from $node_ip${normal}"
        connection_problem="true"
        # Remove problematic node from list
        NODES=("${NODES[@]/$node_ip}")
    fi
}

# Function to get nodes list from external script
#get_nodes_list() {
#    [ "$TS_DEBUG" = true ] && echo -e "
#    [DEBUG] Getting nodes list:
#      Current NODES: ${NODES[*]}
#    "
#
#    # Get nodes list if not already provided
#    if [ -z "${NODES[*]}" ]; then
#        local nodes
#        if [ -n "$NODES_NAME" ]; then
#            nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt "$NODES_TYPE" -nn "$NODES_NAME")
#        else
#            nodes=$(bash "$utils_dir/$get_nodes_list_script" -nt "$NODES_TYPE")
#        fi
#
#        # Check for errors
#        if echo "$nodes" | grep -q "ERROR"; then
#            exit 1
#        else
#            # Add nodes to array
#            for node in $nodes; do
#                NODES+=("$node")
#            done
#        fi
#    fi
#
#    [ "$TS_DEBUG" = true ] && echo -e "
#    [DEBUG] Final NODES list: ${NODES[*]}
#    "
#
#    # Validate nodes list
#    if [ -z "${NODES[*]}" ]; then
#        echo -e "${red}Failed to determine node list - ERROR${normal}"
#        exit 1
#    fi
#}

# Function to get nodes list using external script
get_nodes_list() {
    local param_type="$1"
    local param_value="$2"
    local nodes_result=""

    [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] Getting nodes with: $param_type=$param_value"

    if [ "$param_type" = "return_type" ]; then
        nodes_result=$(bash "$utils_dir/$get_nodes_list_script" -return_type "$param_value")
    else
        if [ -n "$param_value" ]; then
            nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$param_type" "$param_value")
        else
            nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$param_type")
        fi
    fi

    # Check for errors in node list
    if echo "$nodes_result" | grep -q "ERROR"; then
        echo -e "${yellow}Node names could not be determined.${normal}"
        echo -e "${yellow}Try: bash $utils_dir/$get_nodes_list_script -nt all${normal}"
        echo -e "${red}Node names could not be determined - ERROR!${normal}"
        exit 1
    else
        # Add nodes to array
        for node in $nodes_result; do
            NODES+=("$node")
        done
    fi

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Final NODES list: ${NODES[*]}
    "

    # Validate nodes list
    if [ -z "${NODES[*]}" ]; then
        echo -e "${red}Failed to determine node list - ERROR${normal}"
        exit 1
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

# Final user validation
if [[ -z "$SSH_USER" ]]; then
    echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
    exit 1
fi

# Get nodes list
if [ -n "$NODES_NAME" ]; then
    get_nodes_list -nn "$NODES_NAME"
else
    get_nodes_list -nt "$NODES_TYPE"
fi

# Check connections if requested
if [ "$DONT_CHECK_CONN" = false ]; then
    for node_pair in "${NODES[@]}"; do
        node_name="${node_pair%%:*}"
        node_ip="${node_pair#*:}"

        echo "Checking ping to $node_name ($node_ip)"
        check_ping "$node_ip"
    done
fi

# Handle connection problems
if [ "$connection_problem" = true ]; then
    yes_no_input=$(yes_no_answer "Do you want to run a command on nodes without connection problems? [Yes]: ")
    if [ "$yes_no_input" = "true" ]; then
        start_commands_on_nodes
    else
        error_message="Command cancelled. Some nodes have connection problems"
        error_output
    fi
else
    start_commands_on_nodes
fi