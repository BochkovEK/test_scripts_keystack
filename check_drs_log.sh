#!/bin/bash

# Script to display logs from drs service
# Can check logs on specific nodes or automatically detect drs leader

# Colors
normal=$(tput sgr0)
red=$(tput setaf 1)
yellow=$(tput setaf 3)
blue=$(tput setaf 6)
green=$(tput setaf 2)
violet=$(tput setaf 5)

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
[[ -z $DRS_LOG_DIR ]] && DRS_LOG_DIR='/var/log/kolla/drs'
[[ -z $DRS_LOG_FILE_NAME ]] && DRS_LOG_FILE_NAME=$drs_log_file_name
[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=50
[[ -z $DEBUG_STRING_ONLY ]] && DEBUG_STRING_ONLY="false"
[[ -z $CTRL_NAME ]] && CTRL_NAME=""
[[ -z $ALL_CTRL ]] && ALL_CTRL="false"

# Function: display_help
display_help() {
  cat << EOF

The script outputs DRS logs from $DRS_LOG_DIR/$DRS_LOG_FILE_NAME on control nodes

Options:
  -ln,  -line_numbers       <log_last_lines_number>  Number of log lines to display
  -n,   -node_name          <node_name>              Specific node to check
  -dso  -debug_string_only                           Output only DEBUG strings from logs
  -v,   -debug                                       Enable debug output
  -all, -all_ctrl                                    Check logs on all control nodes
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
              LOG_LAST_LINES_NUMBER="$2"
              echo "Found the -line_numbers option, with parameter value $LOG_LAST_LINES_NUMBER"
              shift
              ;;
            -n|-node_name)
              CTRL_NAME="$2"
              echo "Found the -node_name option, with parameter value $CTRL_NAME"
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
              ALL_CTRL="true"
              echo "Found the -all option, with parameter value $ALL_CTRL"
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

    local tail_options="-n ${LOG_LAST_LINES_NUMBER}"

    if [ "$use_follow" = "follow" ]; then
        tail_options="-f -n ${LOG_LAST_LINES_NUMBER}"
    fi

    echo -e "${violet}View full log: ssh -t $SSH_USER@$node_ip sudo less $DRS_LOG_DIR/$DRS_LOG_FILE_NAME${normal}"

    if [ "$DEBUG_STRING_ONLY" = "true" ]; then
        echo -e "${yellow}DEBUG strings only${normal}"
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
          "sudo sh -c 'tail $tail_options $DRS_LOG_DIR/$DRS_LOG_FILE_NAME'" | grep DEBUG
    else
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo sh -c 'tail $tail_options $DRS_LOG_DIR/$DRS_LOG_FILE_NAME'"
    fi
}

# Function: read_logs_from_all_ctrl
check_logs_from_all_ctrl() {
    local nodes="$1"

    for node_info in $nodes; do
        local node_name="${node_info%%:*}"
        echo -e "${blue}Checking $LOG_LAST_LINES_NUMBER line from DRS logs on $node_name...${normal}"
        read_logs "$node_info"
        echo "----------------------------------------"
    done
}

# Function: get_nodes_list
get_nodes_list() {
    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""
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

# Function: find_leader
find_leader() {
    local nodes="$1"
    local leader_drs_ctrl=""

    # If only one node pair provided, check just that node
    if [[ "$nodes" != *" "* ]] && [[ "$nodes" == *":"* ]]; then
        # Single node case
        local node_pair="$nodes"
        local node_name="${node_pair%%:*}"
        local node_ip="${node_pair#*:}"

        [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: Checking single node: $node_pair" >&2

        local leader_exist
        leader_exist=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo sh -c 'tail -n ${LOG_LAST_LINES_NUMBER} $DRS_LOG_DIR/$DRS_LOG_FILE_NAME'" | \
            grep -E 'leadership updated|becomes a leader')

        if [ -n "$leader_exist" ]; then
            leader_drs_ctrl="$node_pair"
            [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: Found leader: $leader_drs_ctrl" >&2
        fi

    else
        # Multiple nodes case
        for node_pair in $nodes; do
            [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: Checking node: $node_pair" >&2

            local node_name="${node_pair%%:*}"
            local node_ip="${node_pair#*:}"

            local leader_exist
            leader_exist=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                "sudo sh -c 'tail -n ${LOG_LAST_LINES_NUMBER} $DRS_LOG_DIR/$DRS_LOG_FILE_NAME'" | \
                grep -E 'leadership updated|becomes a leader')

            if [ -n "$leader_exist" ]; then
                leader_drs_ctrl="$node_pair"
                [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: Found leader: $leader_drs_ctrl" >&2
                break
            fi
        done
    fi

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