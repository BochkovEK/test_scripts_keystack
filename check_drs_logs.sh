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

        -ln,  -line_numbers     <log_last_lines_number>
        -n,   -node_name        <node_name>
        -o,   -output_period    <output_period>
        -v,   -debug            enable debug output (without parameters)
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
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

read_logs () {
  echo -e "${CYAN}Drs logs from $1${NC}"
  ssh -o StrictHostKeyChecking=no $1 tail -${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE
  echo -e "${BLUE}`date`${NC}"
  echo -e "For read all log on $host:"
  echo -e "${ORANGE}ssh -t -o StrictHostKeyChecking=no $1 less $DRS_LOG_FOLDER/$DRS_LOG_FILE${NC}"
}

read_logs_from_all_ctrl () {
  for host in $srv;do
    read_logs $host
  done
}

find_leader () {
  ssh -o StrictHostKeyChecking=no $1 tail -${LOG_LAST_LINES_NUMBER} $DRS_LOG_FOLDER/$DRS_LOG_FILE|grep -e 'leadership updated|becomes a leader'
}

if [ -z "${NODE_NAME}" ]; then
  echo "Try to define DRS leader ctrl node..."

  srv=$(cat /etc/hosts | grep -E "$CTRL_NODES" | awk '{print $1}')
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
        return
      fi
    fi
  done
  if [ -z "${leader_1_exist}" ]; then
    echo -e "${ORANGE}Leader node could not be found${NC}"
    read_logs_from_all_ctrl
  else
    echo -e "${ORANGE}Leader node is: $leader_drs_ctrl${NC}"
    read_logs $leader_drs_ctrl
  fi
else
  read_logs $NODE_NAME
fi

#    ; echo -e "${BLUE}`date`${NC}"
#    echo -e "For read all log on $host:"
#    echo -e "${ORANGE}ssh -t -o StrictHostKeyChecking=no $host less /var/log/kolla/drs/drs.log${NC}"
#  done
