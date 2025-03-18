#!/bin/bash

# The script determines the node for which the nova service is disabled and trying to turn it on
# This script can take the path to the "openrc" file as a parameter (./nova_up.sh /installer/config/openrc)

#OPENRC_PATH=$HOME/openrc

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#CYAN='\033[0;36m'
#BLUE='\033[0;34m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
openstack_utils=$utils_dir/openstack
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
install_package_script="install_package.sh"

edit_ha_region_config_script="edit_ha_region_config.sh"

[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $TRY_TO_RISE ]] && TRY_TO_RISE="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $REGION ]] && REGION="region-ps"
[[ -z $CHECK_IPMI ]] && CHECK_IPMI="true"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"

#======================

# Define parameters
define_parameters () {
  [ "$TS_DEBUG" = true ] && echo "[TS_DEBUG]: \"\$1\": $1"
  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
#  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
}

count=1
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -o,     -openrc             <path_openrc_file>
        -r,     -region             <region_name>
        -dtr,   -dont_try_to_rise   If nova is not active on some nodes, then there will be no attempt to rise it (without parameter)
        -ipmi                       enabled check connection from controls to compute impi (without parameter)
        -v,     -debug              enabled debug output (without parameter)

        To start specify checking:
        bash check_nova_consul.sh <check>

        check list:
        nova    - check nova state (openstack compute service list) and try to raise it for hosts
        ipmi    - check connection from controls to compute impi
"
            exit 0
            break ;;
	-o|-openrc) OPENRC_PATH="$2"
	  echo "Found the -openrc <path_openrc_file> option, with parameter value $OPENRC_PATH"
    shift ;;
  -r|-region) REGION="$2"
	  echo "Found the -region <region_name> option, with parameter value $REGION"
    shift ;;
  -dtr|-dont_try_to_rise) TRY_TO_RISE="false"
	  echo "Found the -dont_try_to_rise, with parameter value $TRY_TO_RISE"
    ;;
  -v|-debug) TS_DEBUG="true"
	  echo "Found the -debug, with parameter value $TS_DEBUG"
    ;;
  -ipmi) CHECK_IPMI="true"
	  echo "Found the -ipmi, with parameter value $CHECK_IPMI"
    ;;
  --) shift
    break ;;
  *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done

# functions

# Check_command
Check_command () {
  printf "%s\n" "${violet}Check $1 command...${normal}"
  command_exist="foo"
  if ! command -v $1 &> /dev/null; then
    command_exist=""
  fi
}

## Check_openstack_cli
#Check_openstack_cli () {
##  printf "%40s\n" "${violet}Check openstack cli...${normal}"
#  Check_command openstack
#  if [ -z $command_exist ]; then
#    echo -e "\033[31mOpenstack cli not installed\033[0m"
#    exit
#  else
#    printf "%s\n" "${green}openstack cli is already installed - success${normal}"
#  fi
#}

# Check_host_command

Check_host_command () {
  if ! bash $utils_dir/$install_package_script host; then
    echo -e "${red}Failed to check 'host' command - ERROR${normal}"
    exit 1
  fi
#  Check_command host
#  if [ -z $command_exist ]; then
#    echo -e "\033[33mbind-utils not installed\033[0m"
#    read -p "Press enter to install bind-utils: "
#    is_sber_os=$(cat /etc/os-release| grep 'NAME="SberLinux"')
#    if [ -n "${is_sber_os}" ]; then
#      yum in -y bind-utils
#    fi
#  else
#    printf "%s\n" "${green}'host' command is available - success${normal}"
#  fi
}

## Check openrc file
#Check_openrc_file () {
#  printf "%s\n" "${violet}Check openrc file here: $OPENRC_PATH${normal}"
#  check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
#  #echo $OPENRC_PATH
#  #echo $check_openrc_file
#  if [ -z "$check_openrc_file" ]; then
#    printf "%s\n" "${red}openrc file not found in $OPENRC_PATH${normal}"
#    exit 1
#  else
#    printf "%s\n" "${green}$OPENRC_PATH file exist - success${normal}"
#  fi
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
    if ! bash $utils_dir/$check_openstack_cli_script; then
      echo -e "${red}Failed to check openstack cli - ERROR${normal}"
      exit 1
    fi
  fi
}

# Check nova srvice list
Check_nova_srvice_list () {
  printf "%s\n" "${violet}Check nova srvice list...${normal}"
  printf "%s\n" "${yellow}openstack compute service list${normal}"
  nova_state_list=$(openstack compute service list)
  echo "$nova_state_list" | \
    sed --unbuffered \
      -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
      -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
      #-e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
}

# Check connection to node
Check_connection_to_node () {
  if ping -c 2 $1 &> /dev/null; then
    printf "%s\n" "${green}There is a connection with $1 - success${normal}"
  else
    printf "%s\n" "${red}No connection with $1 - error!${normal}"
    echo -e "${red}The node may be turned off.${normal}\n"
  fi
}

Switch_case_nodes_type () {
  [ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]: Switch case nodes type...
  "
  case $1 in
      controls)
        nodes=$ctrl_nodes
        ;;
      computes)
        nodes=$comp_nodes
        ;;
      *)
        echo "Unknown node type define"
        return
        ;;
  esac
  [ "$TS_DEBUG" = true ] && echo -e "
    [TS_DEBUG]: \"\$nodes\": $nodes\n
  "
}

# Check connection to nova nodes
Check_connection_to_nodes () {
    printf "%s\n" "${violet}Check connection to $1 nodes...${normal}"

    Switch_case_nodes_type $1

    for host in $nodes; do
        host $host
        sleep 1
        Check_connection_to_node $host
    done
}

# Check connection to impi
Check_connection_to_ipmi () {
  printf "%s\n" "${violet}Check connection from controls to compute impi${normal}"
#  check_openrc_file
#  source $OPENRC_PATH
  [ -z "$nova_state_list" ] && nova_state_list=$(openstack compute service list)
  [ -z "$ctrl_nodes" ] && ctrl_nodes=$(echo "$nova_state_list" | grep -E "(nova-scheduler)" | awk '{print $6}')
  [ -z "$nova_state_list" ] && comp_nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)" | awk '{print $6}')
  suffix_output=$(bash $script_dir/$edit_ha_region_config_script suffix)
  suffix=$(echo "$suffix_output" | tail -n1)
  echo "BMC_SUFFIX: $suffix"

  for ctrl_host in $ctrl_nodes;do
    echo "Check connection from $ctrl_host"
    for comp_host in $comp_nodes; do
#   host $host
      sleep 1
      if ssh $ctrl_host ping -c 2 $comp_host$suffix &> /dev/null; then
        printf "%s\n" "${green}There is a connection with $comp_host$suffix - success${normal}"
      else
        printf "%s\n" "${red}No connection with $comp_host$suffix - error!${normal}"
#        echo -e "${red}The node may be turned off or not resolved host name $comp_host$suffix.${normal}"
      fi
    done
  done
}

# Check disabled computes in nova
Check_disabled_computes_in_nova () {
    printf "%s\n" "${violet}Check disabled computes in nova...${normal}"
    cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')

    # Trying to raise and enable nova service on cmpt
    if [ -n "$cmpt_disabled_nova_list" ]; then
        if [ "$TRY_TO_RISE" = true ] ; then
          for cmpt in $cmpt_disabled_nova_list; do
            while true; do
              read -p "Do you want to try to raise and enable nova service on $cmpt? [Yes]: " yn
              yn=${yn:-"Yes"}
              echo $yn
              case $yn in
                  [Yy]* ) yes_no_input="true"; break;;
                  [Nn]* ) yes_no_input="false"; break ;;
                  * ) echo "Please answer yes or no.";;
              esac
            done
#            echo $yes_no_input
            if [ "$yes_no_input" = "true" ]; then
              try_to_rise="true"
              export CHECK_OPENSTACK="false"
              export COMP_NODE_NAME=$cmpt
              export CHECK_AFTER="false"
              bash $openstack_utils/try_to_rise_node.sh
            fi
          done
          if [ "$try_to_rise" = "true" ]; then
            Check_nova_srvice_list
#            nova_state_list=$(openstack compute service list)
#            echo "$nova_state_list" | \
#              sed --unbuffered \
#                -e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
#                -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
#                -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
          fi
#        cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')
#        if [ -n "$cmpt_disabled_nova_list" ]; then
#          for cmpt in $cmpt_disabled_nova_list; do
#            printf "%40s\n" "${red}Failed to start nova service on $cmpt${normal}"
#          done
##          exit 1
#        fi
      fi
    fi
}

# Check docker container
Check_docker_container () {
    printf "%s\n" "${violet}Check $2 docker on $1 nodes...${normal}"
#    nodes=$(Switch_case_nodes_type $1)
    Switch_case_nodes_type $1
    [ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]: \"\$nodes\": $nodes\n
  "
    for host in $nodes;do
        echo "consul on $host"
        docker=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $host "docker ps | grep $2")
        if [ -z "$docker" ]; then
          [ -z "$docker" ] && echo -e "\033[31mDocker $2 not started on $host\033[0m"
        else
          echo "$docker" | \
              sed --unbuffered \
                  -e 's/\(.*Up.*\)/\o033[92m\1\o033[39m/' \
                  -e 's/\(.*Restarting.*\)/\o033[31m\1\o033[39m/' \
                  -e 's/\(.*unhealthy.*\)/\o033[31m\1\o033[39m/'
        fi
    done
}

# Check members list
Check_members_list () {
    #ctrl_node=$(echo "$comp_and_ctrl_nodes" | grep -E "(nova-scheduler" | awk '{print $6}')
    printf "%s\n" "${violet}Check members list on ${ctrl_node_array[0]}...${normal}"
    members_list=$(ssh -t -o StrictHostKeyChecking=no "${ctrl_node_array[0]}" "docker exec -it consul consul members list")
    echo "$members_list" | \
            sed --unbuffered \
                -e 's/\(.*alive.*\)/\o033[92m\1\o033[39m/' \
                -e 's/\(.*failed.*\)/\o033[31m\1\o033[39m/'
                #-e 's/\(.*Restarting.*\)/\o033[31m\1\o033[39m/' \
                #-e 's/\(.*unhealthy.*\)/\o033[31m\1\o033[39m/'
}

# Check consul logs
Check_consul_logs () {
    printf "%s\n" "${violet}Check consul logs...${normal}"
    #ctrl_node=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)" | awk '{print $6}')
    leader_ctrl_node=$(ssh -t -o StrictHostKeyChecking=no "${ctrl_node_array[0]}" "docker exec -it consul consul operator raft list-peers" | grep leader | awk '{print $1}')
    echo "Leader consul node is $leader_ctrl_node"
    printf  "%s\n" "${yellow}ssh -o StrictHostKeyChecking=no $leader_ctrl_node less /var/log/kolla/autoevacuate.log${normal}"
    ssh -o StrictHostKeyChecking=no "$leader_ctrl_node" tail -15 /var/log/kolla/autoevacuate.log | \
        sed --unbuffered \
        -e 's/\(.*Force off.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*Server.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*Evacuating instance.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*Starting fence.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*IPMI "power off".*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*disabled,.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*state: down.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*CRITICAL.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*WARNING.*\)/\o033[33m\1\o033[39m/';
    ssh -o StrictHostKeyChecking=no -t "$leader_ctrl_node" 'violet=$(tput setaf 5); normal=$(tput sgr0); DATE=$(date); printf "%s\n" "${violet}${DATE}${normal}"'
}

# Check consul config
Check_consul_config () {
  echo
  echo -e "${violet}Check consul config...${normal}"
  [ -n "$OS_REGION_NAME" ] && REGION=$OS_REGION_NAME
  [ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]: \"\$OS_REGION_NAME\": $OS_REGION_NAME\n
  [TS_DEBUG]: \"\$leader_ctrl_node\": $leader_ctrl_node\n
  "
  echo -e "${ORANGE}ssh -t -o StrictHostKeyChecking=no $leader_ctrl_node cat /etc/kolla/consul/region-config_${REGION}.json${NC}"
  ipmi_fencing_state=$(ssh -o StrictHostKeyChecking=no "$leader_ctrl_node" cat /etc/kolla/consul/region-config_"${REGION}".json| \
  grep -E '"bmc": \w|"ipmi": \w|alive_compute_threshold|dead_compute_threshold|"ceph": \w|"nova": \w|"power_fence_mode"')
  echo "Fencing list:"
  echo "$ipmi_fencing_state" | \
            sed --unbuffered \
                -e 's/\(.*true.*\)/\o033[92m\1\o033[39m/' \
                -e 's/\(.*false.*\)/\o033[31m\1\o033[39m/' \
                -e 's/\(.*alive_compute_threshold.*\)/\o033[33m\1\o033[39m/' \
                -e 's/\(.*dead_compute_threshold.*\)/\o033[33m\1\o033[39m/'
}

Get_ctrl_comp_nodes () {
  echo -e "${violet}Get ctrl and comp list from compute service...${normal}"
  nova_state_list=$(openstack compute service list)
  #comp_and_ctrl_nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)|(nova-scheduler)" | awk '{print $6}')
  ctrl_nodes=$(echo "$nova_state_list" | grep -E "(nova-scheduler)" | awk '{print $6}')
  comp_nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)" | awk '{print $6}')
  [ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]: \"\$nova_state_list\": $nova_state_list
  "
#  [TS_DEBUG]: \"\$ctrl_nodes\": $ctrl_nodes\n
#  [TS_DEBUG]: \"\$comp_nodes\": $comp_nodes
#  "
  echo -e "
  ctrl_nodes:
$ctrl_nodes
  comp_nodes:
$comp_nodes
  "

  for i in $ctrl_nodes; do ctrl_node_array+=("$i"); done
}

#clear
##check_openstack_cli
#if [[ $CHECK_OPENSTACK = "true" ]]; then
#  if ! bash $utils_dir/check_openstack_cli.sh; then
#    echo -e "\033[31mFailed to check openstack cli - error\033[0m"
#    exit 1
#  fi
#fi
Check_openstack_cli
Check_and_source_openrc_file
#Check_host_command
Check_nova_srvice_list
Get_ctrl_comp_nodes
[ "$CHECK" = nova ] && { echo "Nova checking..."; Check_nova_srvice_list; Check_disabled_computes_in_nova; exit 0; }
[ "$CHECK" = ipmi ] && { Check_connection_to_ipmi; exit 0; }
Check_connection_to_nodes "controls"
Check_connection_to_nodes "computes"
[ "$CHECK_IPMI" = true ] && { Check_connection_to_ipmi; }
Check_docker_container "controls" consul
Check_docker_container "computes" consul
Check_docker_container "computes" nova_compute
Check_disabled_computes_in_nova
Check_members_list
Check_consul_logs
Check_consul_config