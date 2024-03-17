#!/bin/bash

#----------------------------------------#
#    * KeyStack Installation Script *    #
# Originally written by Alexey Malashin  #
#             - = 2024 =-                #
#----------------------------------------#

DOCKER_COMPOSE_COMMAND='docker compose'

# check os release
os=unknown
[[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })

[[ "$os" == "ditmosos-kolchak" ]] && { DOCKER_COMPOSE_COMMAND='docker-compose'; }

# check for elevated privileges
if ((${EUID:-0} || "$(id -u)")); then
  echo This script has to be run as root or sudo.
  exit 1
fi

###############################
# * Preinstall Phase        * #
# * Asking user for configs * #
###############################

IFS="-"; read -r RELEASE < version; unset IFS
IFS="-"; read -r LCM_R < version_lcm; unset IFS

echo $'\n\n'"*** KeyStack Installer v1.0 ($RELEASE) ***"$'\n\n'

# get installer home dir
if [[ -z "${KS_INSTALL_HOME}" ]]; then
  unset INSTALL_HOME
  read -rp "Enter the home dir for the installation [/installer]: " INSTALL_HOME
else
  INSTALL_HOME=$KS_INSTALL_HOME
fi
export INSTALL_HOME=${INSTALL_HOME:-"/installer"}

# get current machine IP with a try to check it automatically
if [[ -z "${KS_INSTALL_LCM_IP}" ]]; then
  ip=$(hostname -I | { read -r ip _; echo $ip; })
  read -rp "Enter the IP address of this machine [$ip]: " lcm_ip
  lcm_ip=${lcm_ip:-${ip}}
  echo
else
  lcm_ip=$KS_INSTALL_LCM_IP
fi

# get Use client Nexus y/N
if [[ -z "${KS_CLIENT_NEXUS}" ]]; then
  unset CLIENT_NEXUS
  read -rp "Use client artifactory y/n [n]: " CLIENT_NEXUS
else
  CLIENT_NEXUS=$KS_CLIENT_NEXUS
fi
export CLIENT_NEXUS=${CLIENT_NEXUS:-"n"}

if [[ $CLIENT_NEXUS == "y" ]]; then
  #Custom
  #unset CLIENT_NEXUS_NAME
  while [ -z $CLIENT_NEXUS_NAME ]; do
    read -rp "Enter the client Artifactory full domain name for the KeyStack: " CLIENT_NEXUS_NAME
  done
  #Custom
  #unset CLIENT_NEXUS_ADMIN
  while [ -z $CLIENT_NEXUS_ADMIN ]; do
    read -rp "Enter the client Nexus admin name for the KeyStack: " CLIENT_NEXUS_ADMIN
  done
  #Custom
  #unset CLIENT_NEXUS_PASSWORD
  while [ -z $CLIENT_NEXUS_PASSWORD ]; do
    read -rp "Enter the client Nexus password for the KeyStack: " CLIENT_NEXUS_PASSWORD
  done
fi

# get installer root domain name
if [[ -z "${KS_INSTALL_DOMAIN}" ]]; then
  #Custom
  #unset DOMAIN
  while [ -z $DOMAIN ]; do
    read -rp "Enter the root domain name for the KeyStack: " DOMAIN
  done
else
  DOMAIN=$KS_INSTALL_DOMAIN
fi

# get Nexus domain name
if [[ -z "${KS_NEXUS_NAME}" ]]; then
  #Custom
  #unset NEXUS_NAME
  read -rp "Enter the Nexus domain name for the KeyStack [nexus]: " NEXUS_NAME
else
  NEXUS_NAME=$KS_NEXUS_NAME
fi
export NEXUS_NAME=${NEXUS_NAME:-"nexus"}

# get Gitlab domain name
if [[ -z "${KS_GITLAB_NAME}" ]]; then
  unset GITLAB_NAME
  read -rp "Enter the Gitlab domain name for the KeyStack [ks-lcm]: " GITLAB_NAME
else
  GITLAB_NAME=$KS_GITLAB_NAME
fi
export GITLAB_NAME=${GITLAB_NAME:-"ks-lcm"}

# get Vault domain name
if [[ -z "${KS_VAULT_NAME}" ]]; then
  unset VAULT_NAME
  read -rp "Enter the Vault domain name for the KeyStack [vault]: " VAULT_NAME
else
  VAULT_NAME=$KS_VAULT_NAME
fi
export VAULT_NAME=${VAULT_NAME:-"vault"}

# get Netbox domain name
if [[ -z "${KS_NETBOX_NAME}" ]]; then
  unset NETBOX_NAME
  read -rp "Enter the Netbox domain name for the KeyStack [netbox]: " NETBOX_NAME
else
  NETBOX_NAME=$KS_NETBOX_NAME
fi
export NETBOX_NAME=${NETBOX_NAME:-"netbox"}

# get Use Self-signed certificate y/N
if [[ -z "${KS_SELF_SIG}" ]]; then
  #Custom
  #unset SELF_SIG
  read -rp "Use installer Self-signed certificate y/n [y]: " SELF_SIG
else
  SELF_SIG=$KS_SELF_SIG
fi
export SELF_SIG=${SELF_SIG:-"y"}

## ask the user if everything is good
cat <<-END
*** Provided settings: ***
Installer HOME: $INSTALL_HOME
LCM IP: $lcm_ip
KeyStack Root Domain: $DOMAIN
KeyStack Nexus Domain: $NEXUS_NAME.$DOMAIN
KeyStack Gitlab Domain: $GITLAB_NAME.$DOMAIN
KeyStack Vault Domain: $VAULT_NAME.$DOMAIN
KeyStack Netbox Domain: $NETBOX_NAME.$DOMAIN
KeyStack Use Self-signed certificate: $SELF_SIG
KeyStack Client Nexus Domain: $CLIENT_NEXUS_NAME
END

if [[ -z "${KS_INSTALL_SILENT}" ]]; then
  echo
  echo "Does it look good?"
  read -n1 -srp "Press any key to continue or CTRL+C to break "
  echo
  echo "Awesome! Proceeding with the installation..."
  echo
fi

###########################
# * General preparation * #
###########################

INSTALL_DIR=`pwd`

export RELEASE=$RELEASE
export LCM_R=$LCM_R
export LCM_IP=$lcm_ip
export DOMAIN=$DOMAIN
export NEXUS_NAME=$NEXUS_NAME
export GITLAB_NAME=$GITLAB_NAME
export VAULT_NAME=$VAULT_NAME
export NETBOX_NAME=$NETBOX_NAME
export INSTALL_DIR=$INSTALL_DIR
export BACKUP_HOME=$INSTALL_HOME/backup
export UPDATE_HOME=$INSTALL_HOME/update
export CFG_HOME=$INSTALL_HOME/config
export REPO_HOME=$INSTALL_HOME/repo
export CA_HOME=$INSTALL_HOME/data/ca
export GITLAB_HOME=$INSTALL_HOME/data/gitlab
export GITLAB_RUNNER_HOME=$INSTALL_HOME/data/gitlab-runner
export NEXUS_HOME=$INSTALL_HOME/data/nexus
export VAULT_HOME=$INSTALL_HOME/data/vault
export NGINX_HOME=$INSTALL_HOME/data/nginx
export NETBOX_HOME=$INSTALL_HOME/data/netbox
export SSL_CERT_FILE=$CA_HOME/cert/chain-ca.pem

# save settings
cat >./settings <<-END
export RELEASE=$RELEASE
export LCM_R=$LCM_R
export LCM_IP=$LCM_IP
export DOMAIN=$DOMAIN
export NEXUS_NAME=$NEXUS_NAME
export GITLAB_NAME=$GITLAB_NAME
export VAULT_NAME=$VAULT_NAME
export NETBOX_NAME=$NETBOX_NAME
export INSTALL_DIR=$INSTALL_DIR
export BACKUP_HOME=$BACKUP_HOME
export UPDATE_HOME=$UPDATE_HOME
export INSTALL_HOME=$INSTALL_HOME
export CFG_HOME=$CFG_HOME
export REPO_HOME=$REPO_HOME
export CA_HOME=$CA_HOME
export GITLAB_HOME=$GITLAB_HOME
export GITLAB_RUNNER_HOME=$GITLAB_RUNNER_HOME
export NEXUS_HOME=$NEXUS_HOME
export VAULT_HOME=$VAULT_HOME
export NGINX_HOME=$NGINX_HOME
export NETBOX_HOME=$NETBOX_HOME
export SSL_CERT_FILE=$SSL_CERT_FILE
END

mkdir -p $CFG_HOME $REPO_HOME $BACKUP_HOME $VAULT_HOME $NEXUS_HOME $NETBOX_HOME $UPDATE_HOME
cp settings $CFG_HOME 
cp version $CFG_HOME

## credentials
PASSWORD_NEXUS=cdf9f167-f60e-4360-88d5-84e45fa02a99
echo $PASSWORD_NEXUS > $CFG_HOME/nexus_admin_password
KEYSTACK_REGISTRY_PASSWORD=$PASSWORD_NEXUS
KEYSTACK_REGISTRY_USER=admin
##

####################
# * Certificates * #
####################
function gencrt() {
  cp cert.cnf $CFG_HOME
  openssl genrsa -out $CA_HOME/root/ca.key 2048
  chmod 400 $CA_HOME/root/ca.key
  openssl req -new -x509 -nodes -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=KeyStack Root CA" \
      -key $CA_HOME/root/ca.key -sha256 \
      -days 3650 -out $CA_HOME/root/ca.crt
  chmod 444 $CA_HOME/root/ca.crt
  cat $CA_HOME/root/ca.crt > $CA_HOME/cert/chain-ca.pem
  chmod 444 $CA_HOME/cert/chain-ca.pem
  for ca in $NEXUS_NAME $GITLAB_NAME $VAULT_NAME $NETBOX_NAME; do
    openssl genrsa -out $CA_HOME/cert/$ca.key 2048
    openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=$ca.$DOMAIN" \
        -key $CA_HOME/cert/$ca.key -out $CA_HOME/cert/$ca.csr
    export SAN=DNS:$ca.$DOMAIN
    openssl x509 -req -in $CA_HOME/cert/$ca.csr \
        -extfile $CFG_HOME/cert.cnf -CA $CA_HOME/root/ca.crt \
        -CAkey $CA_HOME/root/ca.key -CAcreateserial \
        -out $CA_HOME/cert/$ca.crt -days 728 -sha256
    cat $CA_HOME/cert/$ca.crt $CA_HOME/root/ca.crt > $CA_HOME/cert/chain-$ca.pem
  done
}

mkdir -p $CA_HOME/{root,cert}
if [[ $SELF_SIG == "y" ]]; then
  gencrt
else
  for ca in $NEXUS_NAME $GITLAB_NAME $VAULT_NAME $NETBOX_NAME; do
    [[ ! -f certs/$ca.crt ]] || [[ ! -f certs/$ca.key ]] && echo "Certificate or private key $ca.crt/$ca.key not found in certs" && exit 1
  done
  [[ ! -f certs/ca.crt ]] && echo "CA certificate ca.crt not found in certs" && exit 1
  for ca in $NEXUS_NAME $GITLAB_NAME $VAULT_NAME $NETBOX_NAME; do
    cp certs/$ca.crt $CA_HOME/cert/$ca.crt
    cp certs/$ca.key $CA_HOME/cert/$ca.key
    cat certs/$ca.crt certs/ca.crt > $CA_HOME/cert/chain-$ca.pem
  done
  cp certs/chain-ca.pem $CA_HOME/cert/chain-ca.pem
  cp certs/ca.crt $CA_HOME/root/ca.crt
  chmod 444 $CA_HOME/root/ca.crt
fi

if [[ $CLIENT_NEXUS == "y" ]]; then
  [[ ! -f certs/$CLIENT_NEXUS_NAME.pem ]] && echo "Chain certificates for $CLIENT_NEXUS_NAME not found in certs" && exit 1
  cp certs/$CLIENT_NEXUS_NAME.pem $CA_HOME/cert/$CLIENT_NEXUS_NAME.pem
fi

#######################
# * GitLab & Runner * #
#######################

mkdir -p $GITLAB_HOME/{data,logs,config/trusted-certs}
mkdir -p $GITLAB_RUNNER_HOME/{certs,builds,cache}
cp $CA_HOME/cert/chain-$GITLAB_NAME.pem $GITLAB_RUNNER_HOME/certs/$GITLAB_NAME.$DOMAIN.crt
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp $CA_HOME/cert/$CLIENT_NEXUS_NAME.pem $GITLAB_RUNNER_HOME/certs/$CLIENT_NEXUS_NAME.crt
fi
cp config-template.toml $GITLAB_RUNNER_HOME
sed -i "s/DOMAIN/$DOMAIN/g" $GITLAB_RUNNER_HOME/config-template.toml
sed -i "s/NEXUS_NAME/$NEXUS_NAME/g" $GITLAB_RUNNER_HOME/config-template.toml
sed -i "s/LCM_R/$LCM_R/g" $GITLAB_RUNNER_HOME/config-template.toml
tr -dc A-Za-z0-9 </dev/urandom | head -c 13 > $CFG_HOME/gitlab_root_password
openssl rand -base64 20 > $CFG_HOME/gitlab_runner_token
ssh-keygen -qt rsa -b 2048 -N "" -f $CFG_HOME/gitlab_key -C "root@gitlab"

##############
# * Netbox * #
##############
mkdir -p $NETBOX_HOME/{postgres,redis,redis-cache} $NETBOX_HOME/netbox/{configuration,media,reports,scripts}
cp netbox-docker/docker-compose.yml $CFG_HOME/netbox-compose.yml
cp -r netbox-docker/env $NETBOX_HOME
cp -r netbox-docker/configuration $NETBOX_HOME/netbox
cp netbox-docker/netbox.dump $CFG_HOME/netbox.dump
grep SUPERUSER_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}' > $CFG_HOME/netbox_admin_password

########################
# * Sonatype Nexus 3 * #
########################

mkdir -p $NEXUS_HOME/{data,blobs,restore-from-backup}
mkdir -p /etc/docker/certs.d/$NEXUS_NAME.$DOMAIN
cp $CA_HOME/cert/chain-ca.pem /etc/docker/certs.d/$NEXUS_NAME.$DOMAIN/ca.crt
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp $CA_HOME/cert/$CLIENT_NEXUS_NAME.pem /etc/docker/certs.d/$CLIENT_NEXUS_NAME/$CLIENT_NEXUS_NAME.crt
fi
chown -R 200:200 $NEXUS_HOME

#######################
# * Hashicorp Vault * #
#######################
mkdir -p $VAULT_HOME/{config,file,logs}
cp vault.json $VAULT_HOME/config
cp policy_secret.hcl $VAULT_HOME/config
cp $CA_HOME/cert/chain-ca.pem $VAULT_HOME/config
if [[ $SELF_SIG == "y" ]]; then
  cat $CA_HOME/root/ca.key $CA_HOME/root/ca.crt > $VAULT_HOME/config/root.pem
else
  openssl genrsa -out /tmp/ca.key 2048
  chmod 400 /tmp/ca.key
  openssl req -new -x509 -nodes -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=KeyStack Root CA" \
      -key /tmp/ca.key -sha256 \
      -days 3650 -out /tmp/ca.crt
  chmod 444 /tmp/ca.crt
  cat /tmp/ca.key /tmp/ca.crt > $VAULT_HOME/config/root.pem
  rm -f /tmp/ca.*
fi


##########################
# * LCM not Internet * #
##########################
# download images and packages
if [ "$os" == "ubuntu" ] && [ -f lcmpackages-ub22034.gz ]; then
  echo "LCM packages exist => untar and install"
  tar -xf lcmpackages-ub22034.gz
  dpkg -i  packages/*.deb
fi

if [ "$os" == "sberlinux" ] && [ -f lcmpackages-sberlinux.gz ]; then
  echo "LCM packages exist => untar and install"
  tar -xf lcmpackages-sberlinux.gz
  yum install -y packages/*rpm
  systemctl start docker
fi

if [ -f nexus-$LCM_R.tar ]; then
  echo "Nexus image exist => loading"
  docker load -i nexus-$LCM_R.tar
fi

if [ -f nginx-$LCM_R.tar ]; then
  echo "Nginx image exist => loading"
  docker load -i nginx-$LCM_R.tar
fi

##########################
# * Offline Nexus data * #
##########################
if [ -f keystack-$RELEASE-nexus-blob-offline.tar.gz ]; then
    echo "keystack-$RELEASE-nexus-blob-offline.tar.gz exist"
    cp keystack-$RELEASE-nexus-blob-offline.tar.gz $NEXUS_HOME/data/nexus-blob-offline.tar.gz
  else
    echo "try to download keystack-$RELEASE-nexus-blob-offline.tar.gz"
    curl -L https://repo.itkey.com/repository/k-install/keystack-$RELEASE-nexus-blob-offline.tar.gz -o $NEXUS_HOME/data/nexus-blob-offline.tar.gz
fi

if [ -f keystack-$RELEASE-nexus-db-offline.tar.gz ]; then
    echo "keystack-$RELEASE-nexus-db-offline.tar.gz exist."
    cp keystack-$RELEASE-nexus-db-offline.tar.gz $NEXUS_HOME/data/nexus-db-offline.tar.gz
  else
    echo "try to download keystack-$RELEASE-nexus-db-offline.tar.gz"
    curl -L https://repo.itkey.com/repository/k-install/keystack-$RELEASE-nexus-db-offline.tar.gz -o $NEXUS_HOME/data/nexus-db-offline.tar.gz
fi


################################
# RedOS root cert installation # 
################################
[[ "$os" == "redos" ]] && { cp $CA_HOME/root/ca.crt  /etc/pki/ca-trust/source/anchors/;  update-ca-trust; }
################################

####################################
# SberLinux root cert installation #
####################################
[[ "$os" == "sberlinux" ]] && { cp $CA_HOME/root/ca.crt  /etc/pki/ca-trust/source/anchors/;  update-ca-trust; }

################################
# MosOS root cert installation # 
################################
[[ "$os" == "ditmosos-kolchak" ]] && { cp $CA_HOME/root/ca.crt /usr/share/pki/trust/anchors/; update-ca-certificates; }
################################

#################################
# Ubuntu root cert installation # 
#################################
[[ "$os" == "ubuntu" ]] && { cp $CA_HOME/root/ca.crt /usr/local/share/ca-certificates; update-ca-certificates; }
################################

##################################
# add ssh authorized key for lcm #refactor this
echo -e "\n$(cat $INSTALL_HOME/config/gitlab_key.pub)" >> /root/.ssh/authorized_keys
echo -e "$(cat $INSTALL_HOME/config/gitlab_key)" > /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

#####################
# * Configuration * #
#####################

# save install root domain
echo $DOMAIN > $CFG_HOME/root_domain

# copy docker auth config
mkdir -p /root/.docker
cp docker_auth.json /root/.docker/config.json
cp docker_auth.json $CFG_HOME/
sed -i "s/DOMAIN/$DOMAIN/g" /root/.docker/config.json
sed -i "s/DOMAIN/$DOMAIN/g" $CFG_HOME/docker_auth.json
sed -i "s/NEXUS_NAME/$NEXUS_NAME/g" /root/.docker/config.json
sed -i "s/NEXUS_NAME/$NEXUS_NAME/g" $CFG_HOME/docker_auth.json
# Custom
sed -i "s/YWRtaW46Y2RmOWYxNjctZjYwZS00MzYwLTg4ZDUtODRlNDVmYTAyYTk5/$CLIENT_NEXUS_PASSWORD/g" /root/.docker/config.json
sed -i "s/YWRtaW46Y2RmOWYxNjctZjYwZS00MzYwLTg4ZDUtODRlNDVmYTAyYTk5/$CLIENT_NEXUS_PASSWORD/g" $CFG_HOME/docker_auth.json

chmod 600 /root/.docker/config.json
if [[ $CLIENT_NEXUS == "y" ]]; then
  docker login $CLIENT_NEXUS_NAME -u $CLIENT_NEXUS_ADMIN -p $CLIENT_NEXUS_PASSWORD
fi

# copy daemon.json
cp daemon.json /etc/docker/daemon.json
cp compose.yaml $CFG_HOME/

# Nginx settings
mkdir -p $NGINX_HOME/conf.d/certs
cp nginx.conf $NGINX_HOME
sed -i "s/DOMAIN/$DOMAIN/g" $NGINX_HOME/nginx.conf
sed -i "s/NEXUS_NAME/$NEXUS_NAME/g" $NGINX_HOME/nginx.conf
sed -i "s/GITLAB_NAME/$GITLAB_NAME/g" $NGINX_HOME/nginx.conf
sed -i "s/VAULT_NAME/$VAULT_NAME/g" $NGINX_HOME/nginx.conf
sed -i "s/NETBOX_NAME/$NETBOX_NAME/g" $NGINX_HOME/nginx.conf

for ca in $NEXUS_NAME $GITLAB_NAME $VAULT_NAME $NETBOX_NAME; do
  cp $CA_HOME/cert/chain-$ca.pem $NGINX_HOME/conf.d/certs/chain-$ca.pem
  cp $CA_HOME/cert/$ca.key $NGINX_HOME/conf.d/certs/$ca.key
done

# nexus configuration
echo "Unpacking the archive for Nexus. Please wait."
cd $NEXUS_HOME/blobs && sudo tar -xzf $NEXUS_HOME/data/nexus-blob-offline.tar.gz --checkpoint=10000 --checkpoint-action="ttyout=\b->"
cd $NEXUS_HOME/restore-from-backup && sudo tar -xzf $NEXUS_HOME/data/nexus-db-offline.tar.gz
cd $INSTALL_DIR && rm -rf $NEXUS_HOME/data
echo
chown -R 200:200 $NEXUS_HOME
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d nexus
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d nginx
# check for nexus readiness
echo -n Waiting for Nexus readiness
while [ "$(curl -isf https://$NEXUS_NAME.$DOMAIN/service/rest/v1/status | awk 'NR==1 {print $2}')"  != "200" ];
do
    echo -n .; sleep 5
done
echo .
echo Nexus is Ready!
rm -f $NEXUS_HOME/restore-from-backup/*


# starting the services
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d
##project_k netbox start
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/netbox-compose.yml up -d
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml restart nginx

# check for gitlab readiness
echo -n Waiting for GitLab readiness
while [ "$(curl -sf https://$GITLAB_NAME.$DOMAIN/-/readiness | jq -r .status)"  != "ok" ];
do
  echo -n .; sleep 5
done
echo .
echo GitLab is Ready!

#Nexus images
if [ -f keystack-$RELEASE-docker-images.tar ]; then
  docker load -i keystack-$RELEASE-docker-images.tar
  for image in $(cat keystack-$RELEASE-docker-images.txt); do
    if [[ $CLIENT_NEXUS == "y" ]]; then
      echo $image | sed "s/repo.itkey.com/$CLIENT_NEXUS_NAME/" | xargs -I{} docker tag $image {};
      echo $image | sed "s/repo.itkey.com/$CLIENT_NEXUS_NAME/" | xargs -I{} docker push {};
      echo $image | xargs -I{} docker image rm -f {};
      docker images | grep $CLIENT_NEXUS_NAME | awk '{print $1 ":" $2 }' | grep -v lcm | grep -v kolla-ansible | xargs -I{} docker image rm -f {};
    else
      echo $image | sed "s/repo.itkey.com/$NEXUS_NAME.$DOMAIN/" | xargs -I{} docker tag $image {};
      echo $image | sed "s/repo.itkey.com/$NEXUS_NAME.$DOMAIN/" | xargs -I{} docker push {};
      echo $image | xargs -I{} docker image rm -f {};
      docker images | grep $NEXUS_NAME.$DOMAIN | awk '{print $1 ":" $2 }' | grep -v lcm | grep -v kolla-ansible | xargs -I{} docker image rm -f {};
    fi
  done
fi

# Vault unseal and add passwords, kv
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault operator init -key-shares=1 -key-threshold=1 > /vault/config/unseal_info"
for key in $($DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault cat /vault/config/unseal_info | grep "Unseal Key" | awk '{print $4}'); do $DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault vault operator unseal $key; done
for key in $($DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault cat /vault/config/unseal_info | grep "Initial Root" | awk '{print $4}'); do $DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault vault login -no-print $key; done

# ssh routines (generate a key, create data for gitlab API, crate an ssh config and add server (fqdn & short name) to the known hosts
#[ ! -d "$HOME/.ssh" ] && { mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; }
ssh_key="{\"title\":\"Autogenerated\",\"key\":\"$(<$CFG_HOME/gitlab_key.pub)\"}"
#cat <<END > $HOME/.ssh/config
cat <<END >> /etc/ssh/ssh_config
Host $GITLAB_NAME.$DOMAIN
  PreferredAuthentications publickey
  IdentityFile $CFG_HOME/gitlab_key
END
cat <<END >> /etc/ssh/ssh_config
Host $GITLAB_NAME
  PreferredAuthentications publickey
  IdentityFile $CFG_HOME/gitlab_key
END

ssh-keyscan -t rsa -p 2204 "$GITLAB_NAME.$DOMAIN" > $CFG_HOME/gitlab_ssh_key
echo $(<$CFG_HOME/gitlab_ssh_key) >> /etc/ssh/ssh_known_hosts
#echo $(<$CFG_HOME/gitlab_ssh_key) >> $HOME/.ssh/known_hosts
#ssh-keyscan -t rsa -p 2204 "$GITLAB_NAME.$DOMAIN" >> $HOME/.ssh/known_hosts

# register & configure runner
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec gitlab-runner gitlab-runner register -n -r $(<$CFG_HOME/gitlab_runner_token) -u "https://$GITLAB_NAME.$DOMAIN" --template-config /etc/gitlab-runner/config-template.toml
sed -i "s/concurrent = 1/concurrent = 15/g" $GITLAB_RUNNER_HOME/config.toml

# configure Git
git config --system user.email "root@gitlab"
git config --system user.name "ITKey KeyStack"
git config --system --add safe.directory "$REPO_HOME/*"

# get gitlab root user token & create a new group
pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$(<$CFG_HOME/gitlab_root_password)\"}"
token=$(curl -sX POST -H "Content-Type: application/json" -d "$pwd_data" "https://$GITLAB_NAME.$DOMAIN/oauth/token"  | jq -r .access_token)

# add ssh key to gitlab 
curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$ssh_key" "https://$GITLAB_NAME.$DOMAIN/api/v4/user/keys" | jq

#add group project_k, subgroups services and deployments
grp_data_project_k="{\"name\":\"project_k\",\"path\":\"project_k\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
group_id_project_k=$(curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$grp_data_project_k" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups" | jq -r .id)
grp_data_deployments="{\"name\":\"deployments\",\"parent_id\":\"${group_id_project_k}\",\"path\":\"deployments\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
group_id_deployments=$(curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$grp_data_deployments" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups" | jq -r .id)
grp_data_services="{\"name\":\"services\",\"parent_id\":\"${group_id_project_k}\",\"path\":\"services\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
group_id_services=$(curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$grp_data_services" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups" | jq -r .id)

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault auth enable jwt"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "cat /vault/config/chain-ca.pem >> /etc/ssl/certs/ca-certificates.crt"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "cat /vault/config/chain-ca.pem >> /etc/pki/ca-trust/source/anchors/ca.crt; update-ca-trust"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault write auth/jwt/config jwks_url='https://$GITLAB_NAME.$DOMAIN/-/jwks'  bound_issuer='https://$GITLAB_NAME.$DOMAIN'"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault secrets enable -path=secret_v2 -version 2 kv"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault policy write secret_v2/deployments /vault/config/policy_secret.hcl"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault write auth/jwt/role/itkey-deployments - <<EOF
{
  \"role_type\": \"jwt\",
  \"policies\": [\"secret_v2/deployments\"],
  \"token_explicit_max_ttl\": 3600,
  \"user_claim\": \"user_email\",
  \"bound_claims\": {
    \"namespace_id\": [\"${group_id_deployments}\", \"${group_id_services}\"]
  }
}
EOF
"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault kv put -mount=secret_v2 deployments/secrets/job_key value=\"$(<$CFG_HOME/gitlab_key)\""
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault kv put -mount=secret_v2 deployments/secrets/ca.crt value=\"$(<$CA_HOME/cert/chain-ca.pem)\""
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault kv put -mount=secret_v2 deployments/bifrost/rmi user="itkey" password="r00tme""

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault secrets enable -path installer pki"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault secrets tune -max-lease-ttl=43800h installer"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault write installer/config/ca pem_bundle=@vault/config/root.pem"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault write installer/roles/certs allowed_domains="$DOMAIN" allow_subdomains=true max_ttl=17520h ttl=17520h"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault write installer/config/urls issuing_certificates="https://$VAULT_NAME.$DOMAIN/v1/pki/ca"  crl_distribution_points="https://$VAULT_NAME.$DOMAIN/v1/pki/crl""
rm -f $VAULT_HOME/config/root.pem

# Region1 CA configuration
cp $CA_HOME/cert/chain-ca.pem project_k/deployments/region1/certificates/ca/ca-bundle.crt

function push_gitlab_repository() {
  let "i=i+1"
  if [ $i -eq 5 ]; then return 0;fi
  gitlab_project_id=$(curl -skH "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects?search=${repo}&simple=true" | jq .[0].id)
  if [[ $gitlab_project_id == "null" ]];
  then
    sleep 1
    git push -u origin --all -o ci.skip
    git push -u origin --tags -o ci.skip
    push_gitlab_repository
  else
    gitlab_repository_length=$(curl -skH "Authorization: Bearer $token" https://$GITLAB_NAME.$DOMAIN/api/v4/projects/${gitlab_project_id}/repository/tree | jq length)
    if [ "$gitlab_repository_length" == "1" ];
    then
      sleep 1
      git push -u origin --all -o ci.skip
      git push -u origin --tags -o ci.skip
      push_gitlab_repository
    else
      return 0
    fi
  fi
}


##project_k push
mkdir -p $REPO_HOME/project_k/{deployments,services}
cp -R "project_k" "$REPO_HOME"
while IFS="=" read -r repo branch; do
  cd "$REPO_HOME/project_k/$repo" || exit
  while [ "$(curl -s https://$GITLAB_NAME.$DOMAIN/-/readiness | jq -r .status)"  != "ok" ]; do sleep 1; done
  git remote add origin "ssh://git@$GITLAB_NAME.$DOMAIN:2204/project_k/${repo}.git"
  git add .
  git commit -m "Add installer"
  let "i=0"
  push_gitlab_repository
  cd -
done < "./keystack"


##project_k repostitory configuraton
#get token for netbox - run netbox before it
netbox_token=$(curl -X POST -H "Content-Type: application/json" -H "Accept: application/json; indent=4" "https://$NETBOX_NAME.$DOMAIN/api/users/tokens/provision/" --data '{"username": "admin", "password": "'$(<$CFG_HOME/netbox_admin_password)'"}' --insecure | jq .key)
curl -sX PUT -H "Authorization: Bearer $token" -d "visibility=internal" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=GIT_SSL_NO_VERIFY" -F "value=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
if [[ $CLIENT_NEXUS == "y" ]]; then
  curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY_PASSWORD" -F "value=$CLIENT_NEXUS_PASSWORD" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
  curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY_USER" -F "value=$CLIENT_NEXUS_ADMIN"  "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
  curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY" -F "value=$CLIENT_NEXUS_NAME" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
else
  curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY_PASSWORD" -F "value=$KEYSTACK_REGISTRY_PASSWORD" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
  curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY_USER" -F "value=$KEYSTACK_REGISTRY_USER"  "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
  curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY" -F "value=$NEXUS_NAME.$DOMAIN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
fi
curl -sX POST -H "Authorization: Bearer $token" -F "key=NETBOX_TOKEN" -F "value=$netbox_token" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=NETBOX_URI" -F "value=http://$NETBOX_NAME.$DOMAIN:8080" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=CI_REGISTRY" -F 'value=$KEYSTACK_REGISTRY' "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=CI_REGISTRY_IMAGE" -F 'value=$CI_REGISTRY/$CI_PROJECT_PATH' "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=CI_REGISTRY_PASSWORD" -F 'value=$KEYSTACK_REGISTRY_PASSWORD' "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=CI_REGISTRY_USER" -F 'value=$KEYSTACK_REGISTRY_USER' "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_NEXUS" -F "value=https://$NEXUS_NAME.$DOMAIN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_NEXUS_CREDS" -F "value=admin:$PASSWORD_NEXUS" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_NEXUS_BACKUP" -F "value=http://nexus:8081/repository/k-backup/" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=NEXUS_PASSWORD" -F "value=$PASSWORD_NEXUS" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=LCM_IP" -F "value=$LCM_IP" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=DOMAIN" -F "value=$DOMAIN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=INSTALL_HOME" -F "value=$INSTALL_HOME" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=GITLAB_PASSWORD" -F "value=$(<$CFG_HOME/gitlab_root_password)" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=ANSIBLE_FORCE_COLOR" -F "value=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/admin/ci/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=ANSIBLE_STDOUT_CALLBACK" -F "value=yaml" "https://$GITLAB_NAME.$DOMAIN/api/v4/admin/ci/variables" | jq

#project_k deployments configuration
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_addr" -F "value=http://vault:8200" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_engine" -F "value=secret_v2" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_method" -F "value=jwt" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_prefix" -F "value=deployments" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_role" -F "value=itkey-deployments" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_pki" -F "value=installer" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_role_pki" -F "value=certs" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_deployments}/variables" | jq

#project_k services configuration
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_addr" -F "value=http://vault:8200" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_engine" -F "value=secret_v2" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_method" -F "value=jwt" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_prefix" -F "value=deployments" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_role" -F "value=itkey-deployments" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_pki" -F "value=installer" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_role_pki" -F "value=certs" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_services}/variables" | jq

#new changes in gitlab - need to disable scope job token access
ci_prj_id=$(curl -sH "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects?search=ci&simple=true" | jq .[0].id)
curl -sX PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/${ci_prj_id}/job_token_scope"
ci_prj_id=$(curl -sH "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects?search=keystack&simple=true" | jq .[0].id)
curl -sX PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/${ci_prj_id}/job_token_scope"

# remove unneeded env variables
unset SAN

printf "\n\n\n############################################################\n"
echo "#                YOUR INSTALLATION IS READY                #"
printf "############################################################\n\n\n"

echo GitLab root password: $(<$CFG_HOME/gitlab_root_password)
echo GitLab runner token: $(<$CFG_HOME/gitlab_runner_token)
echo GitLab SSH private key: $CFG_HOME/gitlab_key
echo GitLab SSH public key: $CFG_HOME/gitlab_key.pub
echo Nexus admin password: $(<$CFG_HOME/nexus_admin_password)
echo Netbox admin password: $(<$CFG_HOME/netbox_admin_password)
echo Root CA Certificate: $CA_HOME/cert/chain-ca.pem
