#!/bin/bash

#The scrip cleanup all docker data

all_docker_cleanup () {
  while true; do
      read -p "Do you wish to cleanup $item docker data? [Yes]: " yn
      yn=${yn:-"Yes"}
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
process_item() {
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
            docker_cleanup; break;;
          [Nn]* ) exit;;
          * ) echo "Please answer yes or no.";;
      esac
    done
}

# Function for special 'all' processing
process_all() {
    echo "Executing special ALL operation"
    # Your custom action for 'all' here
    # Example: ls -l, perform cleanup, etc.
}

# Validate arguments
if [ "$#" -eq 0 ]; then
    echo "Error: No arguments provided" >&2
    echo "Usage: $0 item1 item2 ..." >&2
    echo "       $0 all (for special operation)" >&2
    exit 1
fi

# Process arguments
for arg in "$@"; do
    if [[ "$arg" == "all" ]]; then
        process_all
    else
        process_item "$arg"
    fi
done

echo "Completed. Processed $# argument(s)."


