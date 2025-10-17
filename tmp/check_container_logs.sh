#!/bin/bash

#The scrip check container logs

default_ssh_user="root"
default_docker_engine="docker"

#Colors
#green=$(tput setaf 2)
red=$(tput setaf 1)
#violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME=""
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
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

      -c, -container_name <container_name>
      -nn, node_name <node_name_list>       example -nn \"comp-01 comp-02 ... comp-N\"
      -nt, -type_of_nodes	<type_of_nodes>   available values: 'ctrl', 'comp', 'net'
"
      exit 0
      break ;;
	  -c|-container_name)
	    CONTAINER_NAME="$2"
	    echo "Found the -container_name <container_name> option, with parameter value $CONTAINER_NAME"
      shift ;;
    -nt|-type_of_nodes)
      NODES_TYPE=$2
      echo "Found the -type_of_nodes  with parameter value $2"
      shift ;;
    -nn|-type_of_nodes)
      NODES_TYPE=$2
      echo "Found the -type_of_nodes  with parameter value $2"
      shift ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done

echo "Nodes for container checking:"
echo "${NODES[*]}"

grep_string="| grep '$CONTAINER_NAME'"
#echo "$grep_string"
[[ -z ${CONTAINER_NAME} ]] && { grep_string=""; }

for host in "${NODES[@]}"; do
  echo "Check container $CONTAINER_NAME on ${host}"
  if ping -c 2 $host &> /dev/null; then
    printf "%40s\n" "There is a connection with $host - ok!"

    ssh -o StrictHostKeyChecking=no $host docker ps $grep_string \
      |sed --unbuffered \
        -e 's/\(.*(unhealthy).*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*restarting.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*(healthy).*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*Up.*\)/\o033[92m\1\o033[39m/'
  else
    printf "%40s\n" "${red}No connection with $host - error!${normal}"
    echo -e "${red}The node may be turned off.${normal}\n"
  fi
done
