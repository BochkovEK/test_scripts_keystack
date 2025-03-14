#!/bin/bash

#!!! Проверка всех контов но анхелси и рестарт
#The scrip check container state on nodes or node

# example nodes list define
# NODES=("<IP_1>" "<IP_2>" "<IP_3>" "...")

#comp_pattern="\-comp\-..($|\s)"
#ctrl_pattern="\-ctrl\-..($|\s)"
#net_pattern="\-net\-..($|\s)"
#nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
get_nodes_list_script="get_nodes_list.sh"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME=""
[[ -z $NODES ]] && NODES=()
[[ -z $CHECK_UNHEALTHY ]] && CHECK_UNHEALTHY="false"
[[ -z $NODES_TYPE ]] && NODES_TYPE=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
#======================

#note_type_func () {
#  case "$1" in
#        ctrl)
#          nodes_to_find=$ctrl_pattern
#          echo "Сontainer will be checked on ctrl nodes"
#          ;;
#        comp)
#          nodes_to_find=$comp_pattern
#          echo "Сontainer will be checked on comp nodes"
#          ;;
#        net)
#          nodes_to_find=$net_pattern
#          echo "Сontainer will be checked on net nodes"
#          ;;
#        *)
#          echo "type is not specified correctly. Сontainers will be checked on ctr, comp, net nodes"
#          ;;
#        esac
#}

#======================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { CONTAINER_NAME=$1; echo "Name container parameter found with value $CONTAINER_NAME"; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      <container_name> as parameter
      -c, 	-container_name		<container_name>
      -nt, 	-type_of_nodes		<type_of_nodes> 'ctrl', 'comp', 'net'
      -check_unhealthy        check only unhealthy containers (without parameter)
      -debug                  enable debug output (without parameter)
"
      exit 0
      break ;;
	  -c|-container_name) CONTAINER_NAME="$2"
	    echo "Found the -container_name <container_name> option, with parameter value $CONTAINER_NAME"
      shift ;;
    -nt|-type_of_nodes) NODES_TYPE=$2
      echo "Found the -type_of_nodes  with parameter value $NODES_TYPE"
#      note_type_func "$2"
      shift ;;
    -check_unhealthy) CHECK_UNHEALTHY="true"
      echo "Found the -check_unhealthy  with parameter value $CHECK_UNHEALTHY"
      ;;
    -debug) TS_DEBUG="true"
      echo "Found the -debug with parameter value $TS_DEBUG"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done

error_output () {
  printf "%s\n" "${yellow}Docker container not checked on $NODES_TYPE nodes${normal}"
  printf "%s\n" "${red}$error_message - error${normal}"
  exit 1
}

get_nodes_list () {
  if [ -z "${NODES[*]}" ]; then
    nodes=$(bash $utils_dir/$get_nodes_list_script -nt $NODES_TYPE)
  fi
#  node=$(cat /etc/hosts | grep -m 1 -E ${nodes_pattern} | awk '{print $2}')
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$node\": $node\n
  "
  for node in $nodes; do NODES+=("$node"); done
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$NODES\": ${NODES[*]}
  "
  #check error
  for word in "${NODES[@]}"; do
    [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    word in NODES: $word
  "
    error_in_NODES=$(echo $word|grep "ERROR")
    if [ -n "$error_in_NODES" ]; then
      echo -e "${yellow}Node names could not be determined. Try running the script: bash ~/test_scripts_keystack/utils/get_nodes_list.sh -nt all${normal}"
      echo -e "${red}Node names could not be determined - ERROR!${normal}"
      exit 1
    fi
  done
  if [ -z "${NODES[*]}" ]; then
    echo -e "${red}Failed to determine node list - ERROR!${normal}"
    exit 1
  fi
}

get_nodes_list

#[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }

#echo "Nodes for container checking:"
#echo "${NODES[*]}"
#
#if [ ${#NODES[@]} -eq 0 ]; then
#  error_message="Node list type of $nodes_to_find is empty"
#  error_output
#fi

[[ "$CHECK_UNHEALTHY" = true  ]] && {
  UNHEALTHY="\(unhealthy\)";
  echo "UNHEALTHY: $UNHEALTHY";
  }

#grep_string="| grep -E \"$UNHEALTHY\\s+$CONTAINER_NAME\""
#grep_string="| grep -E $CONTAINER_NAME"

[ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  CONTAINER_NAME: $CONTAINER_NAME
  grep_string: $grep_string
  "

for host in "${NODES[@]}"; do
  if [ -z $CONTAINER_NAME ]; then
    echo "Check container on ${host}"
  else
    echo "Check container (CONTAINER_NAME: $CONTAINER_NAME) on ${host}"
  fi
  if ping -c 2 $host &> /dev/null; then
    printf "%40s\n" "There is a connection with $host - ok!"

#    ssh -o StrictHostKeyChecking=no $host docker ps $grep_string \
    ssh -o StrictHostKeyChecking=no $host docker ps \
      |sed --unbuffered \
        -e 's/\(.*second.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*(healthy).*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*hours.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*starting).*\)/\o033[33m\1\o033[39m/'\
        -e 's/\(.*(unhealthy).*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*Less than.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*restarting.*\)/\o033[31m\1\o033[39m/'

#        -e 's/\(.*Up.*\)/\o033[92m\1\o033[39m/' \
  else
    printf "%40s\n" "${red}No connection with $host - error!${normal}"
    echo -e "${red}The node may be turned off.${normal}\n"
  fi
done
