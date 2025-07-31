#!/bin/bash

#The scrip cleanup docker data
# example: bash ~/test_scripts_keystack/docker_cleanup.sh $(docker ps -a --format '{{.Names}}' | grep redis)
# example: bash ~/test_scripts_keystack/docker_cleanup.sh all


all_docker_cleanup () {
  while true; do
      read -p "Do you wish to cleanup $item docker data? [No]: " yn
      yn=${yn:-"No"}
      case $yn in
          [Yy]* )
            docker stop $(docker ps -a -q);
            docker rm $(docker ps -a -q);
            docker volume rm $(docker volume ls);
            docker image rm $(docker image ls);
            break;;
          [Nn]* ) exit;;
          * ) echo "Please answer yes or no.";;
      esac
    done
}

# Function for normal argument processing
docker_cleanup() {
    local item="$1"
    echo "Processing item: '$item'"
    while true; do
      read -p "Do you wish to cleanup $item docker data? [Yes]: " yn
      yn=${yn:-"Yes"}
      case $yn in
          [Yy]* )
            CONTAINER_NAME=$item;
            id_docker=$(docker container ls -a | grep $CONTAINER_NAME | awk '{print $1}');
            docker stop $CONTAINER_NAME;
            docker rm $id_docker;
            docker volume rm $CONTAINER_NAME
            break;;
          [Nn]* ) exit;;
          * ) echo "Please answer yes or no.";;
      esac
    done
}

# Check if first argument is 'all'
if [ "$1" = "all" ]; then
    all_docker_cleanup  # Execute special operation
    exit 0
    # Process remaining arguments (if any)
#    if [ "$#" -gt 1 ]; then
#        shift  # Remove 'all' from arguments
#        for arg in "$@"; do
#            docker_cleanup "$arg"
#        done
#    fi
else
    # Process all arguments normally
    for arg in "$@"; do
        docker_cleanup "$arg"
    done
fi

#echo "Done. Processed arguments: $#"


