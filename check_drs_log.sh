#!/bin/bash

CTRL_NODES='\-ctrl\-..( |$)'
#TAIL_NUM=100

CYAN='\033[0;36m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $DRS_LOG_FOLDER ]] && DRS_LOG_FOLDER='/var/log/kolla/drs'
[[ -z $DRS_LOG_FILE ]] && DRS_LOG_FILE='drs.log'
[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=100
[[ -z $OUTPUT_PERIOD ]] && OUTPUT_PERIOD=10
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $DEBUG_STRING_ONLY ]] && DEBUG_STRING_ONLY="false"
[[ -z $ALL_NODES ]] && ALL_NODES="false"
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
        The script output drs logs from $DRS_LOG_FOLDER/$DRS_LOG_FILE on control nodes

        -ln,  -line_numbers       <log_last_lines_number>
        -n,   -node_name          <node_name>
        -o,   -output_period      <output_period>
        -dso  -debug_string_only  output from logs debug string only (without parameters)
        -v,   -debug              enable debug output (without parameters)
        -all                      check logs on all ctrl nodes
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
    -v|-debug) DEBUG="true"
      echo "Found the -debug option, with parameter value $DEBUG"
      ;;
    -dso|-debug_string_only) DEBUG_STRING_ONLY="true"
      echo "Found the -debug_string_only option, with parameter value $DEBUG_STRING_ONLY"
      ;;
    -all) ALL_NODES="true"
      echo "Found the -all option, with parameter value $ALL_NODES"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

read_logs () {
  echo -e "${CYAN}Drs $LOG_LAST_LINES_NUMBER lines logs from $1${NC}"
  if [ "$DEBUG_STRING_ONLY" = true ]; then
    echo -e "${ORANGE}DEBUG strings only${NC}"
    ssh -o StrictHostKeyChecking=no $1 tail -${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE|grep "DEBUG"
  else
    ssh -o StrictHostKeyChecking=no $1 tail -${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE
  fi
  echo -e "${BLUE}`date`${NC}"
  echo -e "For read all log on $1:"
  echo -e "${ORANGE}ssh -t -o StrictHostKeyChecking=no $1 less $DRS_LOG_FOLDER/$DRS_LOG_FILE${NC}"
}

periodic_read_logs () {
  while true; do
    echo -e "Output period check: $OUTPUT_PERIOD sec"
    read_logs $1
    sleep $OUTPUT_PERIOD
  done
}

read_logs_from_all_ctrl () {
  for host in $srv;do
    read_logs $host
  done
}

find_leader () {
  ssh -o StrictHostKeyChecking=no $1 tail -${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE|grep -E 'leadership updated|becomes a leader'
}

srv=$(cat /etc/hosts | grep -E "$CTRL_NODES" | awk '{print $1}')

[ "$DEBUG" = true ] && echo -e "
  [DEBUG]:
  NODE_NAME: $NODE_NAME
  "

if [ -n "${NODE_NAME}" ]; then
  echo "Read logs from $NODE_NAME..."
  periodic_read_logs $NODE_NAME
elif [ "$ALL_NODES" = true ]; then
  echo "Read logs from all nodes..."
  read_logs_from_all_ctrl
else
  echo "Try to define DRS leader ctrl node..."

  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: srv: $srv
  "
  leader_1_exist=""
  leader_2_exist=""
  for host in $srv;do
#    echo -e "${CYAN}Drs logs on $(cat /etc/hosts | grep -E ${host} | awk '{print $2}'):${NC}"
    [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: host: $host
    "
    if [ -z "${leader_1_exist}" ]; then
      [ "$DEBUG" = true ] && { echo -e "
  [DEBUG]: find_leader:"; find_leader; }
      leader_1_exist=$(find_leader $host)
      leader_drs_ctrl=$host
      [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: leader_1_exist: $leader_1_exist
      "
    else
      leader_2_exist=$(find_leader $host)
      if [ -n "${leader_2_exist}" ]; then
        [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: leader_2_exist: $leader_2_exist
        "
        echo -e "${ORANGE}Leader node could not be found${NC}"
        read_logs_from_all_ctrl
      fi
    fi
  done
  if [ -z "${leader_1_exist}" ]; then
    echo -e "${ORANGE}Leader node could not be found${NC}"
    read_logs_from_all_ctrl
  else
    echo -e "${ORANGE}Leader node is: $leader_drs_ctrl${NC}"
    periodic_read_logs $leader_drs_ctrl
  fi
fi

#    ; echo -e "${BLUE}`date`${NC}"
#    echo -e "For read all log on $host:"
#    echo -e "${ORANGE}ssh -t -o StrictHostKeyChecking=no $host less /var/log/kolla/drs/drs.log${NC}"
#  done
