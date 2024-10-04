#!/bin/bash

#The scrip stop and delete volume, image container by name

#"\-comp\-..$"
comp_pattern="\-comp\-.."
ctrl_pattern="\-ctrl\-.."
net_pattern="\-net\-.."
nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME=""
[[ -z $NODE_NAME ]] && NODE_NAME=""
[[ -z $DEBUG ]] && DEBUG="false"

note_type_func () {
  case "$1" in
    ctrl)
      nodes_to_find=$ctrl_pattern
      echo "Container will be checked on ctrl nodes"
      ;;
    comp)
      nodes_to_find=$comp_pattern
      echo "Container will be checked on comp nodes"
      ;;
    net)
      nodes_to_find=$net_pattern
      echo "Container will be checked on net nodes"
      ;;
    *)
      echo "type is not specified correctly. Containers will be checked on ctr, comp, net nodes"
      ;;
  esac
}

docker_command () {
    id_docker=$(ssh -o StrictHostKeyChecking=no $1 "docker container ls --format 'table {{.ID}}\t{{.Names}}' -a|grep -E \"\s${CONTAINER_NAME}\$\"|awk '{print \$1}'")
  if [ -n "$id_docker" ]; then
    echo "id_docker $CONTAINER_NAME on $1: $id_docker"
    id_image=$(ssh -o StrictHostKeyChecking=no $1 docker images | grep $CONTAINER_NAME | awk '{print $3}')
    echo "id_image $CONTAINER_NAME on $host: $id_docker"
    ssh -o StrictHostKeyChecking=no $1 docker stop $CONTAINER_NAME
    ssh -o StrictHostKeyChecking=no $1 docker rm $id_docker
    ssh -o StrictHostKeyChecking=no $1 docker volume rm $CONTAINER_NAME
    ssh -o StrictHostKeyChecking=no $1 docker rmi $id_image
  else
    echo "$CONTAINER_NAME not found"
  fi
}

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { CONTAINER_NAME=$1; echo "Container name parameter found with value $CONTAINER_NAME"; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      -c,   -container_name   <container_name>
      -nt,  -type_of_nodes    <type_of_nodes> 'ctrl', 'comp', 'net'
      -nn,  -node_name        <node_name>     <stand_name>-keystack-<type>-<number>
      -debug                  enabled debug output (without parameter)
"
      exit 0
      break ;;
	-c|-container_name) CONTAINER_NAME="$2"
	  echo "Found the -container_name option, with parameter value $CONTAINER_NAME"
    shift ;;
  -nn|-node_name) NODE_NAME="$2"
    echo "Found the -node_name option, with parameter value $NODE_NAME"
    shift ;;
  -nt|-type_of_nodes)
    echo "Found the -type_of_nodes option, with parameter value $2"
    note_type_func "$2"
    shift ;;
  -debug) DEBUG="true"
    echo "Found the -debug, with parameter value $DEBUG"
    ;;
  --) shift
    break ;;
  *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
    esac
    shift
done


[[ -z "${CONTAINER_NAME}" ]] && echo "Container name required as parameter script" && exit 1

[ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  CONTAINER_NAME: $CONTAINER_NAME
  NODE_NAME:      $NODE_NAME
  nodes_to_find:  $nodes_to_find
"

if [ -z "$NODE_NAME" ]; then
  srv=$(cat /etc/hosts | grep -E "$nodes_to_find" | awk '{print $1}')
  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  srv: $srv
"
  read -p "Press enter to continue"
  for host in $srv;do
    docker_command $host
  done
else
  docker_command $NODE_NAME
fi

#container_name=consul
#id_image=$(docker images | grep $container_name | awk '{print $3}')
#echo $id_image
#docker rmi $id_image

