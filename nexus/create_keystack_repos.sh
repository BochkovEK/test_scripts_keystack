#!/bin/bash

#The script created keystack repos by json files

DOCKER_HTTP="http://localhost:8081/service/rest/v1/repositories"
USER="admin"
PASSWORD="password"

# k-images docker(hosted)
curl -v -u $USER:$PASSWORD -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/docker/hosted" -d @docker-hosted-k-images.json
# docker-sber yum(hosted)
curl -v -u $USER:$PASSWORD -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/yum/hosted" -d @yum-hosted-docker-sber.json
# sberlinux yum(hosted)
curl -v -u $USER:$PASSWORD -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/yum/hosted" -d @yum-hosted-sberlinux.json
# images raw(hosted)
curl -v -u $USER:$PASSWORD -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @raw-hosted-images.json
# k-add raw(hosted)
curl -v -u $USER:$PASSWORD -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @raw-hosted-k-add.json
# k-backup raw(hosted)
curl -v -u $USER:$PASSWORD -H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/raw/hosted" -d @raw-hosted-k-backup.json
# k-pip pypi(hosted)
curl -v -u $USER:$PASSWORD-H "Connection: close" -H "Content-Type: application/json" -X POST "$DOCKER_HTTP/pypi/hosted" -d @pypi-hosted-k-pip.json
