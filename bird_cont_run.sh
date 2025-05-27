#!/bin/bash

docker stop $(docker ps -a|grep bird_custom|awk '{print $1}')
docker rm $(docker ps -a|grep bird_custom|awk '{print $1}')

  #--privileged

docker run -d \
  --cap-add=NET_ADMIN \
  --cap-add=NET_BROADCAST \
  --cap-add=NET_RAW \
  --cap-add=SYS_PTRACE \
  --name bird_custom $(docker inspect bird --format='{{json .Mounts}}' | python3 -c '
import json, sys;
mounts = json.load(sys.stdin);
print(" ".join([
    "-v " + (m["Source"] + ":" + m["Destination"] if m["Type"] == "bind"
           else m["Name"] + ":" + m["Destination"])
    for m in mounts
]))
') \
  --network host \
  -e KOLLA_CONFIG_STRATEGY="COPY_ALWAYS" \
  repo.itkey.com/project_k/bird:ks2025.1.1-sberlinux \
  dumb-init --single-child -- kolla_start