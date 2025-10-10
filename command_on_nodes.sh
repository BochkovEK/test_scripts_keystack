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
blue=$(tput setaf 6)

# Default values
[[ -z $COMMAND ]] && COMMAND="ls -la"
[[ -z $NODES ]] && NODES=()
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $PING ]] && PING="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $DONT_CHECK_CONN ]] && DONT_CHECK_CONN="true"
#[[ -z $SEND_ENVS ]] && SEND_ENVS=""

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
      -debug                          Enable debug mode
      --help                          Show this help message

    Examples:
      Remove all containers on all nodes:
        bash command_on_nodes.sh -c 'docker stop \$(docker ps -a -q)'
        bash command_on_nodes.sh -c 'docker system prune -af'
        bash command_on_nodes.sh -c 'docker volume prune -af'
      Copy file to nodes:
        export FILE_CONTENT=\$(cat /path/to/file);
        bash ~/test_scripts_keystack/command_on_nodes.sh -u kolla -nt all -c \"echo '\$FILE_CONTENT' > /path/to/file; cat /path/to/file\"
    "
}
#-se, -send_envs                 Send envs like -se \"MY_VARIABLE='value'\"
#                                      (exp: export FOO=bar; bash ~/test_scripts_keystack/command_on_nodes.sh -se \$FOO -u kolla -nt all -c \"echo \$FOO\")

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

#-se|-send_envs)
#           SEND_ENVS="$2"
#           echo "Found -send_envs option with value: $SEND_ENVS"
#           shift
#           ;;

# Function to display error messages and exit
error_output() {
    echo "${yellow}Command not executed on $NODES_TYPE nodes${normal}"
    echo "${red}$error_message - error${normal}"
    exit 1
}

# Standalone SSH check function that can be used independently
test_ssh_connection() {
    local node_name="$1"
    local node_ip="$2"
    local timeout="${3:-10}"

    echo -e "${blue}Testing SSH connection to $node_name...${normal}"

    # Check if required variables are set
    if [ -z "$SSH_USER" ]; then
        echo -e "${red}SSH_USER variable is not set${normal}"
        return 1
    fi

    if [ -z "$node_ip" ]; then
        echo -e "${red}Node IP is not specified${normal}"
        return 1
    fi

    # Test basic connectivity with ping first (optional)
    if command -v ping &> /dev/null; then
        if ping -c 1 -W 2 "$node_ip" &> /dev/null; then
            echo -e "${green}✓ Host $node_ip is reachable${normal}"
        else
            echo -e "${yellow}⚠ Host $node_ip is not responding to ping${normal}"
        fi
    fi

    # Test SSH connection
    local ssh_output
    ssh_output=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$timeout -o BatchMode=yes \
        "$SSH_USER@$node_ip" "echo 'SUCCESS'; whoami; hostname" 2>&1)

    local ssh_exit_code=$?

    if [ $ssh_exit_code -eq 0 ]; then
        local remote_user=$(echo "$ssh_output" | sed -n '2p')
        local remote_hostname=$(echo "$ssh_output" | sed -n '3p')
        echo -e "${green}✓ SSH connection successful${normal}"
        echo -e "${green}  Connected as: $remote_user${normal}"
        echo -e "${green}  Remote host: $remote_hostname${normal}"
        return 0
    else
        echo -e "${red}✗ SSH connection failed${normal}"
        # Provide more detailed error information
        case $ssh_exit_code in
            255)
                echo -e "${red}  Error: Network connection refused or host unreachable${normal}"
                ;;
            5)
                echo -e "${red}  Error: Host key verification failed${normal}"
                ;;
            1)
                echo -e "${red}  Error: Authentication failed${normal}"
                ;;
            *)
                echo -e "${red}  Error: SSH connection failed (exit code: $ssh_exit_code)${normal}"
                ;;
        esac
        return 1
    fi
}

# Function to check SSH connectivity to a node
check_ssh_connectivity() {
    local node_name="$1"
    local node_ip="$2"

    echo -e "Checking SSH connectivity to $node_name ($node_ip)"

    # Try to connect with timeout and execute a simple command
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
        "$SSH_USER@$node_ip" "echo 'SSH connection successful'" 2>/dev/null; then
        echo -e "✓ SSH connection to $node_name ($node_ip) is working"
        return 0
    else
        echo -e "${red}✗ SSH connection to $node_name ($node_ip) failed${normal}"
        return 1
    fi
}

# Function to execute commands on all nodes
start_commands_on_nodes() {
    if [ "$TS_DEBUG" = true ]; then
        echo -e "
    [DEBUG] Nodes list:"
        for host in "${NODES[@]}"; do
            echo "$host"
        done
    fi

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
#        if [ -n "$SEND_ENV" ]; then
#            [ "$TS_DEBUG" = true ] && echo -e "
#    [DEBUG] Executing command: ssh -o StrictHostKeyChecking=no -t \"$SEND_ENV\" \"$SSH_USER@$node_ip\" \"$COMMAND\""
#            export "$SEND_ENV" ssh -o StrictHostKeyChecking=no -t "$SEND_ENV" "$SSH_USER@$node_ip" "$COMMAND"
#        else
        # First check SSH connectivity
        if ! check_ssh_connectivity "$node_name" "$node_ip"; then
            echo -e "${red}Cannot check containers on $node_name - SSH connection failed${normal}"
            continue
        fi
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Executing command: ssh -o StrictHostKeyChecking=no -t \"$SSH_USER@$node_ip\" \"$COMMAND\""
#        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "$COMMAND"
        ssh -o StrictHostKeyChecking=no -t "$SSH_USER@$node_ip" "$COMMAND"
#        fi
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

# Get ssh user
get_ssh_user () {
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
}


# Main execution

get_ssh_user

# Get nodes list
if [ -n "$NODES_NAME" ]; then
    nodes=$(get_nodes_list "-nn" "$NODES_NAME")
else
    nodes=$(get_nodes_list "-nt" "$NODES_TYPE")
fi

if [ "$TS_DEBUG" = true ]; then
#    get_nodes_list "-nn" "$NODES_NAME"
#    get_nodes_list "-nt" "$NODES_TYPE"
    echo -e "
    [DEBUG] nodes: $nodes
    "
fi

IFS=' ' read -ra NODES <<< "$nodes"

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