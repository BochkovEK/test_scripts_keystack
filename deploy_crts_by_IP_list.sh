#!/bin/bash

# The script for deploing pub keys from gitlab and lcm, nexus and docker crts, by IPs list


IPS=("<IP_1>" "<IP_2>" "<IP_3>" "...")
INSTALL_HOME=/installer

[[ -z "${1}" ]] && echo -e "Installer houme by default: $INSTALL_HOME" || INSTALL_HOME=$1

SETTINGS=$INSTALL_HOME/config/settings
KEY=$(cat $INSTALL_HOME/config/gitlab_key.pub)

source $SETTINGS

copy_pub_keys () {
    for IP in "${IPS[@]}"; do
        echo "Copy keys to ${IP}"
        ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub $IP
        ssh -o StrictHostKeyChecking=no $IP echo '"$KEY"' >> ~/.ssh/authorized_keys
    done
}

copy_crts () {
    for IP in "${IPS[@]}"; do
        echo "Copy crts to ${IP}"
        ssh -o StrictHostKeyChecking=no $IP mkdir -p /etc/docker/certs.d/nexus.$DOMAIN:5000
        scp -o StrictHostKeyChecking=no $INSTALL_HOME/data/ca/installer/certs/nexus.crt $IP:/etc/docker/certs.d/nexus.$DOMAIN:5000/nexus.crt
        ssh -o StrictHostKeyChecking=no $IP chmod 444 /etc/docker/certs.d/nexus.$DOMAIN:5000/nexus.crt
        ssh -o StrictHostKeyChecking=no $IP mkdir -p ~/.docker
        scp -o StrictHostKeyChecking=no $INSTALL_HOME/config/docker_auth.json $IP:~/.docker/config.json
        ssh -o StrictHostKeyChecking=no $IP chmod 600 ~/.docker/config.json
    done 
}

copy_pub_keys
copy_crts
