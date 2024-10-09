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

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"

[[ -z $LOG_LAST_LINES_NUMBER ]] && LOG_LAST_LINES_NUMBER=25
[[ -z $OUTPUT_PERIOD ]] && OUTPUT_PERIOD=10
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc
#========================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { NODE_NAME=$1; echo "Node name parameter found with value $NODE_NAME"; }
  [ "$count" = 2 ] && [[ -n $1 ]] && { OUTPUT_PERIOD=$1; echo "Check period parameter found with value $OUTPUT_PERIOD"; }
  [ "$count" = 3 ] && [[ -n $1 ]] && { LOG_LAST_LINES_NUMBER=$1; echo "log last lines number parameter found with value $LOG_LAST_LINES_NUMBER"; }
}

## Check openrc file
#check_and_source_openrc_file () {
#    echo "Check openrc file and source it..."
#    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
#    if [ -z "$check_openrc_file" ]; then
#        printf "%s\n" "${red}openrc file not found in $OPENRC_PATH - ERROR!${normal}"
#        exit 1
#    fi
#    source $OPENRC_PATH
#    #export OS_PROJECT_NAME=$PROJECT
#}

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

#  Check_command openstack
#  if [ -z $command_exist ]; then
#    echo -e "\033[31mOpenstack cli not installed\033[0m"
#    exit
#  else
#    printf "%s\n" "${green}openstack cli is already installed - success${normal}"
#  fi


  if [[ $CHECK_OPENSTACK = "true" ]]; then
#    echo -e "${violet}Check openstack cli...${normal}"
    if ! bash $utils_dir/check_openstack_cli.sh; then
      echo -e "${red}Failed to check openstack cli - ERROR${normal}"
      exit 1
    fi
  fi
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -ln,  -line_numbers     <log_last_lines_number>
      -n,   -node_name        <node_name>
      -o,   -output_period    <output_period>

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
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

#if ! bash $utils_dir/check_openstack_cli.sh; then
#    exit 1
#fi

#check_openstack_cli
Check_openstack_cli
# Check openrc file
Check_and_source_openrc_file

if [ -z "${NODE_NAME}" ]; then

# Check nova srvice list
  nova_state_list=$(openstack compute service list)
  #nova_nodes_list=$(echo "$nova_state_list" | grep -E "nova-compute|nova-scheduler" | awk '{print $6}')
  ctrl_nodes_list=$(echo "$nova_state_list" | grep -E "nova-scheduler" | awk '{print $6}')
  #nova_nodes_arr=("$nova_nodes_list")
  for i in $ctrl_nodes_list; do nova_ctrl_arr+=("$i"); done;
    ctrl_node=${nova_ctrl_arr[0]}
    leader_ctrl_node=$(ssh -t -o StrictHostKeyChecking=no "$ctrl_node" "docker exec -it consul consul operator raft list-peers" | grep leader | awk '{print $1}')
    NODE_NAME=$leader_ctrl_node
  echo "Leader consul node is $NODE_NAME"
else
  NODE_NAME=$1
fi

#clear

echo -e "Consul logs from $NODE_NAME node"
echo -e "Output period check: $OUTPUT_PERIOD sec"

while :
do
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

    sleep "$OUTPUT_PERIOD"
done
