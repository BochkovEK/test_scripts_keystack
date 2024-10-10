#!/bin/bash

# The script displays logs from the consul service
# The node from which the log is checked is determined by the NODE_NAME variable. This variable can be set as the first parameter when running the script
# The check period is determined by the OUTPUT_PERIOD variable. This variable can be set as the second parameter when running the script

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yallow=$(tput setaf 3)
cyan=$(tput setaf 14)

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"

[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=25
[[ -z $OUTPUT_PERIOD ]] && OUTPUT_PERIOD=10
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $CTRL_LIST ]] && CTRL_LIST=""
[[ -z $ALL_CTRL ]] && ALL_CTRL="true"
#========================


# Define parameters
define_parameters () {
#  echo foo
  [ "$count" = 1 ] && [[ -n $1 ]] && { NODE_NAME=$1; echo "Node name parameter found with value $NODE_NAME"; }
  [ "$count" = 2 ] && [[ -n $1 ]] && { OUTPUT_PERIOD=$1; echo "Check period parameter found with value $OUTPUT_PERIOD"; }
  [ "$count" = 3 ] && [[ -n $1 ]] && { LOG_LAST_LINES_NUMBER=$1; echo "log last lines number parameter found with value $LOG_LAST_LINES_NUMBER"; }
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -ln,  -line_numbers     <log_last_lines_number>
      -n,   -node_name        <node_name>
      -o,   -output_period    <output_period>
      -ctrl_list              <ctrl_list> example: -ctrl_list \"ctrl-01 ctrl-02 ctrl-02\"
      -all_ctrl               check logs on all ctrl nodes (without parameter)

      Example satart command:
        bash $HOME/test_scripts_keystack/chack_consul_log.sh <ctrl_01> <check_period> <log last lines number>
        bash $HOME/test_scripts_keystack/chack_consul_log.sh ebochkov-ks-sber-ctrl-01 10 25
"
#      -e,   -send_env       \"<ENV_NAME=env_value>\"
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
    -ctrl_list) CTRL_LIST="$2"
      echo "Found the -ctrl_list option, with parameter value $CTRL_LIST"
      shift ;;
    -all_ctrl) ALL_CTRL="true"
      echo "Found the -all_ctrl option, with parameter value $ALL_CTRL"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

# Check openrc file
Check_and_source_openrc_file () {
  echo -e "${violet}Check openrc file...${normal}"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    echo -e "${green}$openrc_file file exist - success${normal}"
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    echo -e "${red}openrc file not found in $openrc_file${normal} - ERROR"
    exit 1
  fi
}

# Сheck openstack cli
Check_openstack_cli () {
  if [[ $CHECK_OPENSTACK = "true" ]]; then
    if ! bash $utils_dir/check_openstack_cli.sh; then
#      echo -e "${red}Failed to check openstack cli - ERROR${normal}"
      exit 1
    fi
  fi
}


#check_openstack_cli
Check_openstack_cli
# Check openrc file
Check_and_source_openrc_file

if [ -z "${NODE_NAME}" ]; then
  echo "Attempt to identify a leader in the consul cluster and read logs..."
  if [ -z "${CTRL_LIST}" ]; then
    nova_state_list=$(openstack compute service list)
    ctrl_nodes_list=$(echo "$nova_state_list" | grep -E "nova-scheduler" | awk '{print $6}')
    if [ -z "${ctrl_nodes_list}" ]; then
      echo -e "${yallow}Failed to determine node control list${normal}"
      echo -e "Try Try passing the list of node controls via the key \'-ctrl_list\' (read --help)"
      echo -e "${red}Failed to determine node control list - ERROR${normal}"
      exit 1
    fi
  else
    ctrl_nodes_list=$CTRL_LIST
  fi
    for i in $ctrl_nodes_list; do nova_ctrl_arr+=("$i"); done
    if [ ! "$ALL_CTRL" = true ]; then
#    if [ -z "${ALL_CTRL}" ]; then
      first_ctrl_node=${nova_ctrl_arr[0]}
      leader_ctrl_node=$(ssh -t -o StrictHostKeyChecking=no "$first_ctrl_node" "docker exec -it consul consul operator raft list-peers" | grep leader | awk '{print $1}')
      if [ -z "${leader_ctrl_node}" ]; then
        NODE_NAME=$ctrl_nodes_list
        echo -e "${yallow}Check logs on ctrl_nodes_list: \'$ctrl_nodes_list\' nodes${normal}"
      else
        NODE_NAME=$leader_ctrl_node
        echo "Leader consul node is $NODE_NAME"
      fi
    else
      echo -e "${yallow}Check logs on all ctrl nodes${normal}"
      NODE_NAME=$ctrl_nodes_list
#      NODE_NAME=$ALL_CTRL
    fi
#else
#  NODE_NAME=$1
fi

#clear

echo -e "Consul logs from $NODE_NAME node"
echo -e "Output period check: $OUTPUT_PERIOD sec"

while :
do
  for ctrl in $NODE_NAME; do
    echo -e "${cyan}Check logs on $ctrl...${normal}"
    ssh -o StrictHostKeyChecking=no "$NODE_NAME" tail -n $LOG_LAST_LINES_NUMBER /var/log/kolla/autoevacuate.log | \
        sed --unbuffered \
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
        -e 's/\(.*Starting fence.*\)/\o033[33m\1\o033[39m/'

    ssh -o StrictHostKeyChecking=no "$NODE_NAME" 'echo -e "\033[0;35m$(date)\033[0m
\033[0;35mLogs from: $(hostname)\033[0m
\033[0;35mFor check this log: \033[0m
\033[0;35mssh $(hostname) less /var/log/kolla/autoevacuate.log | less\033[0m"'
  done
  sleep "$OUTPUT_PERIOD"
done
