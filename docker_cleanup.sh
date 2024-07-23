#!/bin/bash

#The scrip cleanup all docker data

docker_cleanup () {
  docker stop $(docker ps -a -q);
  docker rm $(docker ps -a -q);
  docker volume rm $(docker volume ls);
  docker image rm $(docker image ls)
}

while true; do
    read -p "Do you wish to cleanup all docker data? [No]: " yn
    yn=${yn:-"No"}
    case $yn in
        [Yy]* ) docker_cleanup; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done