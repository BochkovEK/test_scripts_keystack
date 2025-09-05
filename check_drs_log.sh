#!/bin/bash

script_dir=$(dirname $0)
utils_dir="$script_dir/utils"
nodes_type="ctrl"
get_nodes_list_script="get_nodes_list.sh"
drs_log_file_name="drs-api-error.log"
default_ssh_user="root"
#check_openrc_script="check_openrc.sh"

#Colors
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 14)
#green=$(tput setaf 2)
#violet=$(tput setaf 5)

#CTRL_NODES='\-ctrl\-..( |$)'
#TAIL_NUM=100

#CYAN='\033[0;36m'
#BLUE='\033[0;34m'
#ORANGE='\033[0;33m'
#NC='\033[0m' # No Color

[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $DRS_LOG_FOLDER ]] && DRS_LOG_FOLDER='/var/log/kolla/drs'
[[ -z $DRS_LOG_FILE_NAME ]] && DRS_LOG_FILE_NAME=$drs_log_file_name
[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=50
[[ -z $OUTPUT_PERIOD ]] && OUTPUT_PERIOD=10
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $DEBUG_STRING_ONLY ]] && DEBUG_STRING_ONLY="false"
[[ -z $ALL_NODES ]] && ALL_NODES="false"
#[[ -z $USER ]] && USER="$default_user"
#==============================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [ "$1" = foo ] && { FOO=true; echo "Check FOO parameter found"; }
#  [ "$count" = 1 ] && [ "$1" = check ] && { ONLY_CONF_CHECK=true; echo "Only conf check parameter found"; }
}

count=1
while [ -n "$1" ]; do
    case "$1" in
        --help) echo -E "
        The script output drs logs from $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME on control nodes

        -ln,  -line_numbers       <log_last_lines_number>
        -n,   -node_name          <node_name>
        -o,   -output_period      <output_period>
        -dso  -debug_string_only  output from logs debug string only (without parameters)
        -v,   -debug              enable debug output (without parameters)
        -all                      check logs on all ctrl nodes
        -u, user                  set user for ssh access
"
      exit 0
      break ;;
    -ln|-line_numbers) LOG_LAST_LINES_NUMBER="$2"
      echo "Found the -line_numbers option, with parameter value $LOG_LAST_LINES_NUMBER"
      shift ;;
    -n|-node_name) NODE_NAME="$2"
      echo "Found the -node_name option, with parameter value $NODE_NAME"
      shift ;;
    -o|-output_period) OUTPUT_PERIOD="$2"
      echo "Found the -output_period option, with parameter value $OUTPUT_PERIOD"
      shift ;;
    -v|-debug) TS_DEBUG="true"
      echo "Found the -debug option, with parameter value $TS_DEBUG"
      ;;
    -dso|-debug_string_only) DEBUG_STRING_ONLY="true"
      echo "Found the -debug_string_only option, with parameter value $DEBUG_STRING_ONLY"
      ;;
    -all) ALL_NODES="true"
      echo "Found the -all option, with parameter value $ALL_NODES"
      ;;
    -u|-user) SSH_USER=$2
      echo "Found the -user  with parameter value $SSH_USER"
      shift
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

# Read log from one ctrl node
read_logs () {
  local node_pair=$1
  local node_name="${node_pair%%:*}"
  local node_ip="${node_pair#*:}"

  echo -e "${cyan}Drs $LOG_LAST_LINES_NUMBER lines logs from $node_name${normal}"
  if [ "$DEBUG_STRING_ONLY" = true ]; then
    echo -e "${yellow}DEBUG strings only${normal}"
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo sh -c 'tail -f -n ${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'|grep DEBUG"
  else
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo sh -c 'tail -f -n ${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'"
  fi
  echo -e "${blue}`date`${normal}"
  echo -e "For read all log on $node_name:"
  echo -e "${yellow}ssh -o StrictHostKeyChecking=no \"$SSH_USER@$node_ip\" \"sudo sh -c 'less $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'\"${normal}"
}

#periodic_read_logs () {
#  while true; do
#    echo -e "Output period check: $OUTPUT_PERIOD sec"
#    read_logs $1
#    sleep $OUTPUT_PERIOD
#  done
#}

read_logs_from_all_ctrl () {
  local nodes=$1
  for node_pair in $nodes;do
    read_logs "$node_pair"
  done
}

find_leader () {
  local node_pair=$1
  local node_name="${node_pair%%:*}"
  local node_ip="${node_pair#*:}"
  ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo sh -c 'tail -n ${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE_NAME'|grep -E 'leadership updated|becomes a leader'"
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

#debug echo
debug_echo () {
  echo -e "
  [DEBUG]:
    $1"
}

# Main execution

get_ssh_user

# Get nodes list
if [ -n "$NODES_NAME" ]; then
    nodes=$(get_nodes_list "-nn" "$NODES_NAME")
else
    nodes=$(get_nodes_list "-nt" ctrl)
fi

#NODES=("${nodes[@]}")

#[ "$TS_DEBUG" = true ] && { for string in "${NODES[@]}"; do debug_echo "$string"; done; }
[ "$TS_DEBUG" = true ] && { echo $nodes; }

if [ -n "${NODE_NAME}" ]; then
  echo "Read logs from \"$nodes\"..."
  read_logs "$nodes"
#  periodic_read_logs $NODE_NAME
elif [ "$ALL_NODES" = true ]; then
  echo "Read logs from all nodes..."
  read_logs_from_all_ctrl "$nodes"
else
  echo "Try to define DRS leader ctrl node..."
#  leader_1_exist=""
#  leader_2_exist=""
  leader_drs_ctrl=""
  for node_pair in $nodes; do
#    echo -e "${CYAN}Drs logs on $(cat /etc/hosts | grep -E ${host} | awk '{print $2}'):${normal}"
    [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: node_pair: $node_pair
    "
    if [ -z "${leader_drs_ctrl}" ]; then
      [ "$TS_DEBUG" = true ] && { echo -e "
  [DEBUG]: find_leader:"; find_leader; }
      leader_exist=$(find_leader "$node_pair")
      if [ -n "${leader_exist}" ]; then
        leader_drs_ctrl="$node_pair"
        [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
      leader_exist: $leader_exist
      leader_drs_ctrl: $leader_drs_ctrl
      "
      fi
#    else
#      leader_2_exist=$(find_leader "$node_pair")
#      if [ -n "${leader_2_exist}" ]; then
#        [ "$TS_DEBUG" = true ] && echo -e "
#  [DEBUG]: leader_2_exist: $leader_2_exist
#        "
#        echo -e "${yellow}Leader node could not be found${normal}"
#        read_logs_from_all_ctrl
#      fi
    fi
  done

  if [ -z "${leader_exist}" ]; then
    echo -e "${yellow}Leader node could not be found${normal}"
    read_logs_from_all_ctrl
  else
    echo -e "${yellow}Leader node is: $leader_drs_ctrl${normal}"
    read_logs "$leader_drs_ctrl"
#    periodic_read_logs $leader_drs_ctrl
  fi
fi

#    ; echo -e "${BLUE}`date`${normal}"
#    echo -e "For read all log on $host:"
#    echo -e "${yellow}ssh -t -o StrictHostKeyChecking=no $host less /var/log/kolla/drs/drs.log${normal}"
#  done
