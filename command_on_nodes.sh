#!/bin/bash

# Script to execute commands on multiple nodes
# Requires node IPs and names to be defined in /etc/hosts

# Color definitions
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
blue=$(tput setaf 6)

# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
check_ssh_connectivity_script="check_ssh_connectivity.sh"
default_ssh_user="root"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
    "$utils_dir/$check_ssh_connectivity_script"
)

# Default values
[[ -z $COMMAND ]] && COMMAND="ls -la"
[[ -z $NODES ]] && NODES=""
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $DONT_CHECK_CONN ]] && DONT_CHECK_CONN="true"
[[ -z $SSH_KEY_PATH ]] && SSH_KEY_PATH=""

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Execute commands on multiple nodes. Node IPs and names must be defined in /etc/hosts.

    Options:
      -c, -command <command>          Command to execute on nodes
      -nt, -type_of_nodes <type>      Node type: 'lcm', 'ctrl', 'comp', 'net', 'strg', 'all'
      -nn, -node_name <names>         Specific node names (space-separated)
      -u, -user <username>            SSH username
      -check_conn                     Check connection before executing commands
      -key, -ssh_key_path             Path to private ssh key
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

# Function to define parameters from positional arguments
define_parameters() {
    [ "$count" = 1 ] && [[ -n $1 ]] && {
        COMMAND="$1"
        echo "Command parameter found with value: $COMMAND"
    }
}

# Parse command line arguments
# Parse command line arguments
while [ -n "$1" ]; do
  case "$1" in
    --help)
      # ... твой help остается без изменений ...
      exit 0
      ;;

    -debug|--debug)
      TS_UTILS_DEBUG="true"
      [ "$TS_UTILS_DEBUG" = true ] && echo -e "Debug mode enabled"
      ;;

    -nt|-type_of_nodes)
      NODES_TYPE="$2"
      [ "$TS_UTILS_DEBUG" = true ] && echo -e "Node type set to: $NODES_TYPE"
      shift
      ;;

    -suffix)
      RMI_SUFFIX="$2"
      [ "$TS_UTILS_DEBUG" = true ] && echo -e "RMI suffix set to: $RMI_SUFFIX"
      shift
      ;;

    -nn|-nodes_name)
      NODES_NAME="$2"
      [ "$TS_UTILS_DEBUG" = true ] && echo -e "Node names set to: $NODES_NAME"
      shift
      ;;

    -return_type)
      RETURN_TYPE_NODE_NAME="$2"
      [ "$TS_UTILS_DEBUG" = true ] && echo -e "Return type for node: $RETURN_TYPE_NODE_NAME"
      shift
      ;;

    -h|-hosts_path)
      TS_HOSTS_PATH="$2"
      [ "$TS_UTILS_DEBUG" = true ] && echo -e "Hosts file path set to: $TS_HOSTS_PATH"
      shift
      ;;

    --)
      shift
      break
      ;;

    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;

    *)
      if [ -z "$NODES_TYPE" ] || [ "$NODES_TYPE" = "all" ]; then
        NODES_TYPE="$1"
        [ "$TS_UTILS_DEBUG" = true ] && echo -e "Nodes type parameter found with value: $NODES_TYPE"
      else
        echo "Warning: extra positional argument ignored: $1" >&2
      fi
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

# Function to check SSH connectivity to a node
check_ssh_connectivity() {
    local node_pair=$1
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"

    if test_ssh_connection "$node_name" "$node_ip" "10" "$SSH_USER" "$SSH_KEY_PATH" > /dev/null 2>&1; then
        echo -e "✓ SSH connection successful"
        return 0
    else
        echo -e "${red}✗ SSH connection failed${normal}"
        return 1
    fi
}

# Function to execute commands on all nodes
start_commands_on_nodes() {
    if [ "$TS_DEBUG" = true ]; then
        echo -e "
    [DEBUG] Nodes list: $NODES"
    fi

    # Validate nodes list
    if [ -z "$NODES" ]; then
        error_message="Failed to compile the list of nodes ($NODES_TYPE)"
        error_output
    fi

    # Execute command on each node
    for node_pair in $NODES; do
        # Split node:ip format
        node_name="${node_pair%%:*}"
        node_ip="${node_pair#*:}"
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] node_name: $node_name; node_ip: $node_ip"
        echo -e "${blue}Executing command on ${node_name}${normal}"

        # Check SSH connectivity using external module (which includes ping check)
        if ! check_ssh_connectivity "$node_pair"; then
            echo -e "${red}Cannot execute command on $node_name - SSH connection failed${normal}"
            continue
        fi

        if [ -n "$SSH_KEY_PATH" ]; then
            SSH_KEY="-i $SSH_KEY_PATH"
            echo $SSH_KEY
        else
            SSH_KEY=""
        fi
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] Executing command: ssh -o StrictHostKeyChecking=no -t $SSH_KEY \"$SSH_USER@$node_ip\" \"$COMMAND\""
        ssh -o StrictHostKeyChecking=no -t $SSH_KEY "$SSH_USER@$node_ip" "$COMMAND"
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

#    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

    if ! nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@" 2>&1); then
#        exit_code=$?
        echo -e "${red}ERROR: Node list script failed${normal}" >&2
        echo -e "${red}Output: $nodes_result${normal}" >&2
        return 1
    fi

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
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    echo -e "Using SSH user: $SSH_USER"

    # Get nodes list
    if [ -n "$NODES_NAME" ]; then
        NODES=$(get_nodes_list "-nn" "$NODES_NAME")
    else
        NODES=$(get_nodes_list "-nt" "$NODES_TYPE")
    fi

    if [ "$TS_DEBUG" = true ]; then
        echo -e "
    [DEBUG] nodes: $NODES
    "
    fi

    start_commands_on_nodes
}

# Run main function
main "$@"