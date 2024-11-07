#!/bin/bash

#The script copy file to nodes

script_dir=$(dirname $0)
script_name=$(basename "$0")
utils_dir=$script_dir/utils
get_nodes_list_script="get_nodes_list.sh"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $NODES ]] && NODES=()
[[ -z $NODES_TYPE ]] && NODES_TYPE=""
[[ -z $TS_SOURCE ]] && TS_SOURCE=""
[[ -z $TS_DESTINATION ]] && TS_DESTINATION=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"


count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      ip and name nodes list needed in /etc/hosts

      -nn
      -nt,  -type_of_nodes  <type_of_nodes> 'ctrl', 'comp', 'net'
      -s,   -src            <source_file_path>
      -d,   -dest           <destination_file_path_on_node>
      --debug               debug mode
      Example:
        bash $script_name -nt ctrl -s ~/foo/bar -d ~/baz
"
        exit 0
        break ;;
    -s|-src) TS_SOURCE="$2"
      echo "Found the -src option, with parameter value $TS_SOURCE"
      shift ;;
    -nt|-type_of_nodes) NODES_TYPE=$2
      echo "Found the -type_of_nodes, with parameter value $NODES_TYPE"
      shift ;;
    -d|-dest) TS_DESTINATION="$2"
      echo "Found the -dest option, with parameter value $TS_DESTINATION"
      shift ;;
    -nn|-node_name)
      for i in $2; do NODES+=("$i"); done
      echo "Found the -nn option, with parameter value ${NODES[*]}"
      shift ;;
    -debug) TS_DEBUG="true"
      echo "Found the -debug parameter"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1 not allowed"; exit 0; };;
    esac
    shift
done


error_output () {
  printf "%s\n" "${yellow}Command not executed on $NODES_TYPE nodes${normal}"
  printf "%s\n" "${red}$error_message - error${normal}"
  exit 1
}

## Define parameters
#define_parameters () {
#  [ "$count" = 1 ] && [[ -n $1 ]] && { COMMAND=$1; echo "Command parameter found with value $COMMAND"; }
#}

get_nodes_list () {
  if [ -z "${NODES[*]}" ]; then
    nodes=$(bash $utils_dir/$get_nodes_list_script -nt $NODES_TYPE)
  fi
  if echo $nodes| grep "ERROR"; then
#    echo -e "$nodes"
    exit 1
  fi
#  node=$(cat /etc/hosts | grep -m 1 -E ${nodes_pattern} | awk '{print $2}')
#  [ "$TS_DEBUG" = true ] && echo -e "
#  [DEBUG]: \"\$node\": $node\n
#  "
  for node in $nodes; do NODES+=("$node"); done
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$NODES\": ${NODES[*]}
  "
  echo -e "
  NODES: ${NODES[*]}
  "
  if [ -z "${NODES[*]}" ]; then
    echo -e "${red}Failed to determine node list - ERROR${normal}"
    exit 1
  fi
}

get_nodes_list

[ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    TS_SOURCE:      $TS_SOURCE
    TS_DESTINATION: $TS_DESTINATION
"

for node in $NODES;do
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    node: $node
    command:
      scp $TS_SOURCE ${node}:${TS_DESTINATION}
  "
  scp $TS_SOURCE ${node}:${TS_DESTINATION}
done

#script_dir=$(dirname $0)
#nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)|\-net\-..( |$)|\-lcm\-..( |$)'
#parses_file=/etc/hosts

#srv=$(cat $parses_file | grep -E "$nodes_to_find" | awk '{print $1}')
#for host in $srv;do
#  scp $parses_file $host:$parses_file
#done