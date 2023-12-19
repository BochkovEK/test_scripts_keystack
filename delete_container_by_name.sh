#!/bin/bash

# Сделать ключи и параметры для удаления с одной ноды
#The scrip stop and delete volume, image container by name

[[ -z "${1}" ]] && echo "Container name requaired as parameter script" && exit 1

nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)'
#|\-net\-..( |$)'

srv=$(cat /etc/hosts | grep -E "$nodes_to_find" | awk '{print $1}')

for host in $srv;do
    id_docker=$(ssh -o StrictHostKeyChecking=no $host docker container ls -a | grep $1 | awk '{print $1}')
    echo "id_docker $1 on $host: $id_docker"
    id_image=$(ssh -o StrictHostKeyChecking=no $host docker images | grep $1 | awk '{print $3}')
    echo "id_image $1 on $host: $id_docker"
    ssh -o StrictHostKeyChecking=no $host docker stop $1
    ssh -o StrictHostKeyChecking=no $host docker rm $id_docker
    ssh -o StrictHostKeyChecking=no $host docker volume rm $1
    ssh -o StrictHostKeyChecking=no $host docker rmi $id_image
done

#container_name=consul
#id_image=$(docker images | grep $container_name | awk '{print $3}')
#echo $id_image
#docker rmi $id_image

