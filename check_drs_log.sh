#!/bin/bash

# Script to display logs from drs service
# Can check logs on specific nodes or automatically detect drs leader

# Colors
normal=$(tput sgr0)
red=$(tput setaf 1)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 14)
green=$(tput setaf 2)

# Script configuration
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
nodes_type="ctrl"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
drs_log_file_name="drs-api-error.log"
default_ssh_user="root"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
)

# Default configuration values
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $DRS_LOG_FOLDER ]] && DRS_LOG_FOLDER='/var/log/kolla/drs'
[[ -z $DRS_LOG_FILE_NAME ]] && DRS_LOG_FILE_NAME=$drs_log_file_name
[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=50
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $DEBUG_STRING_ONLY ]] && DEBUG_STRING_ONLY="false"
[[ -z $ALL_NODES ]] && ALL_NODES="false"
#[[ -z $OUTPUT_PERIOD ]] && OUTPUT_PERIOD=10

# Function: define_parameters
define_parameters() {
  [ "$count" = 1 ] && [ "$1" = foo ] && {
    FOO=true;
    echo "Check FOO parameter found";
  }
}

# Function: display_help
display_help() {
  cat << EOF

The script outputs DRS logs from $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME on control nodes

Options:
  -ln,  -line_numbers       <log_last_lines_number>  Number of log lines to display
  -n,   -node_name          <node_name>              Specific node to check
  -dso  -debug_string_only                           Output only DEBUG strings from logs
  -v,   -debug                                       Enable debug output
  -all                                               Check logs on all control nodes
  -u,   -user               <user>                   Set user for SSH access
  --help                                            Display this help message

Examples:
  $0 -n node-01                 # Show logs from specific node
  $0 -all                       # Show logs from all control nodes
  $0 -dso -ln 100               # Show 100 DEBUG lines only

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
              validate_numeric_argument "$2" "line numbers"
              LOG_LAST_LINES_NUMBER="$2"
              echo "Found the -line_numbers option, with parameter value $LOG_LAST_LINES_NUMBER"
              shift
              ;;
            -n|-node_name)
              NODE_NAME="$2"
              echo "Found the -node_name option, with parameter value $NODE_NAME"
              shift
              ;;
            -v|-debug)
              TS_DEBUG="true"
              echo "Found the -debug option, with parameter value $TS_DEBUG"
              ;;
            -dso|-debug_string_only)
              DEBUG_STRING_ONLY="true"
              echo "Found the -debug_string_only option, with parameter value $DEBUG_STRING_ONLY"
              ;;
            -all)
              ALL_NODES="true"
              echo "Found the -all option, with parameter value $ALL_NODES"
              ;;
            -u|-user)
              SSH_USER="$2"
              echo "Found the -user option with parameter value $SSH_USER"
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

# Function: read_logs
read_logs() {
    local node_pair="$1"
    local use_follow="${2:-false}"
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"

    echo -e "${cyan}DRS $LOG_LAST_LINES_NUMBER lines logs from $node_name${normal}"

    local tail_command="tail -n ${LOG_LAST_LINES_NUMBER}"

    if [ "$use_follow" = "true" ]; then
        tail_command="tail -f"
    fi

    if [ "$DEBUG_STRING_ONLY" = "true" ]; then
        echo -e "${yellow}DEBUG strings only${normal}"
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
          "sudo sh -c '$tail_command $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'" | grep DEBUG
    else
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo sh -c '$tail_command $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'"
    fi

    echo -e "${blue}$(date)${normal}"
    echo -e "To read all logs on $node_name:"
    echo -e "${yellow}ssh -o StrictHostKeyChecking=no \"$SSH_USER@$node_ip\" \"sudo sh -c 'less $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'\"${normal}"
}

# Function: read_logs_from_all_ctrl
read_logs_from_all_ctrl() {
    local nodes="$1"

    for node_pair in $nodes; do
        read_logs "$node_pair"
        echo -e "${yellow}--------------------------------------------------${normal}"
    done
}

# Function: find_leader
find_leader() {
    local node_pair="$1"
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"

    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo sh -c 'tail -n ${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'" | \
        grep -E 'leadership updated|becomes a leader'
}

# Function: get_nodes_list
get_nodes_list() {
    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
      nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$*\")"

    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG] nodes_result: $nodes_result
    "

    # Validate node list results
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

# Function: get_ssh_user
get_ssh_user() {
    # Use provided user or try to determine current user
    if [[ -z "$SSH_USER" ]]; then
        SSH_USER=$(whoami 2>/dev/null) || {
          echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
          SSH_USER="$default_ssh_user"
        }
    fi

    # Final validation
    if [[ -z "$SSH_USER" ]]; then
        echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
        exit 1
    fi

    echo -e "${blue}Using SSH user: $SSH_USER${normal}"
}

# Function: debug_echo
debug_echo() {
    echo -e "
    [DEBUG]:
      $1"
}

# Function: find_drs_leader
find_drs_leader() {
    local nodes="$1"
    local leader_drs_ctrl=""

    for node_pair in $nodes; do
        [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: Checking node: $node_pair" >&2

        local leader_exist
        leader_exist=$(find_leader "$node_pair")

        if [ -n "$leader_exist" ]; then
          leader_drs_ctrl="$node_pair"
          [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: Found leader: $leader_drs_ctrl" >&2
          break
        fi
    done

    echo "$leader_drs_ctrl"
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

# Then in main code:
echo -e "${cyan}Attempting to identify DRS leader node...${normal}"
leader_drs_ctrl=$(find_drs_leader "$nodes")

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
    if [ -n "$NODE_NAME" ]; then
        OPERATION="specific_node"
        NODES=$(get_nodes_list "-nn" "$NODE_NAME")
        echo -e "${cyan}Reading logs from specific node: $NODE_NAME${normal}"
    elif [ "$ALL_NODES" = "true" ]; then
        OPERATION="all_nodes"
        NODES=$(get_nodes_list "-nt" "$nodes_type")
        echo -e "${cyan}Reading logs from all control nodes${normal}"
    else
        OPERATION="auto_leader"
        NODES=$(get_nodes_list "-nt" "$nodes_type")
        echo -e "${cyan}Attempting to identify DRS leader node automatically${normal}"
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "${blue}Nodes: $NODES${normal}"

    # Execute the determined operation
    case "$OPERATION" in
        "specific_node")
            read_logs "$NODES"
            ;;
        "all_nodes")
            read_logs_from_all_ctrl "$NODES"
            ;;
        "auto_leader")
            leader_drs_ctrl=$(find_drs_leader "$NODES")
            if [ -z "$leader_drs_ctrl" ]; then
                echo -e "${yellow}Leader node could not be identified${normal}"
                echo -e "${yellow}Falling back to reading logs from all nodes${normal}"
                read_logs_from_all_ctrl "$NODES"
            else
                echo -e "${green}Leader node identified: $leader_drs_ctrl${normal}"
                read_logs "$leader_drs_ctrl" "true"
            fi
            ;;
    esac

    echo -e "${blue}Script execution completed at: $(date)${normal}"
}

main "$@"