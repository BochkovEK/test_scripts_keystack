#!/bin/bash
set -x
#----------------------------------------#
#    * KeyStack Installation Script *    #
# Originally written by Alexey Malashin  #
#             - = 2024 =-                #
#----------------------------------------#
DOCKER_COMMAND='podman'
DOCKER_COMPOSE_COMMAND='podman compose'

# check os release
os=unknown
[[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })

[[ "$os" == "ditmosos-kolchak" ]] && { DOCKER_COMPOSE_COMMAND='docker compose'; }

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
IFS="-"; read -r BASE < version-base; unset IFS

echo $'\n\n'"*** KeyStack Installer v1.0 ($RELEASE-$BASE) ***"$'\n\n'

export ITKEY_REPO_FQDN="registry.ks2025.1.fstec.private.itkey.com"

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
  read -rp "Use remote\existing Artifactory y/n [n]: " CLIENT_NEXUS
else
  CLIENT_NEXUS=$KS_CLIENT_NEXUS
fi
export CLIENT_NEXUS=${CLIENT_NEXUS:-"n"}

if [[ $CLIENT_NEXUS == "y" ]]; then
  if [[ -z "${KS_CLIENT_NEXUS_NAME}" ]]; then
    unset CLIENT_NEXUS_NAME
    while [ -z $CLIENT_NEXUS_NAME ]; do
      read -rp "Enter the remote\existing Artifactory FQDN for the KeyStack: " CLIENT_NEXUS_NAME
    done
  else
    CLIENT_NEXUS_NAME=$KS_CLIENT_NEXUS_NAME
  fi
  if [[ -z "${KS_CLIENT_NEXUS_ADMIN}" ]]; then
    unset CLIENT_NEXUS_ADMIN
    while [ -z $CLIENT_NEXUS_ADMIN ]; do
      read -rp "Enter the remote\existing Artifactory user name: " CLIENT_NEXUS_ADMIN
    done
  else
    CLIENT_NEXUS_ADMIN=$KS_CLIENT_NEXUS_ADMIN
  fi
  if [[ -z "${KS_CLIENT_NEXUS_PASSWORD:7}" ]]; then
    unset CLIENT_NEXUS_PASSWORD
    while [ -z ${CLIENT_NEXUS_PASSWORD:7} ]; do
      read -rp "Enter the remote\existing Artifactory password(at least 8 characters): " CLIENT_NEXUS_PASSWORD
    done
  else
    CLIENT_NEXUS_PASSWORD=$KS_CLIENT_NEXUS_PASSWORD
  fi
fi

# get Use LDAP for Gitlab and Netbox y/N
if [[ -z "${KS_LDAP_USE}" ]]; then
  unset LDAP_USE
  read -rp "Enable auth LDAP for Gitlab and Netbox y/n [n]: " LDAP_USE
else
  LDAP_USE=$KS_LDAP_USE
fi
export LDAP_USE=${LDAP_USE:-"n"}

if [[ $LDAP_USE == "y" ]]; then
  # Get use LDAP configs
  if [[ -z "${KS_LDAP_SERVER_URI}" ]]; then
    unset LDAP_SERVER_URI
    while [ -z $LDAP_SERVER_URI ]; do
      read -rp "Enter the LDAP Server URI: " LDAP_SERVER_URI
    done
  else
    LDAP_SERVER_URI=$KS_LDAP_SERVER_URI
  fi
  if [[ -z "${KS_LDAP_BIND_DN}" ]]; then
    unset LDAP_BIND_DN
    while [ -z $LDAP_BIND_DN ]; do
      read -rp "Enter the LDAP BIND DN: " LDAP_BIND_DN
    done
  else
    LDAP_BIND_DN=$KS_LDAP_BIND_DN
  fi
  if [[ -z "${KS_LDAP_BIND_PASSWORD}" ]]; then
    unset LDAP_BIND_PASSWORD
    while [ -z ${LDAP_BIND_PASSWORD} ]; do
      read -rp "Enter the LDAP BIND Password: " LDAP_BIND_PASSWORD
    done
  else
    LDAP_BIND_PASSWORD=$KS_LDAP_BIND_PASSWORD
  fi
  if [[ -z "${KS_LDAP_USER_SEARCH_BASEDN}" ]]; then
    unset LDAP_USER_SEARCH_BASEDN
    while [ -z $LDAP_USER_SEARCH_BASEDN ]; do
      read -rp "Enter the LDAP USER SEARCH BASEDN: " LDAP_USER_SEARCH_BASEDN
    done
  else
    LDAP_USER_SEARCH_BASEDN=$KS_LDAP_USER_SEARCH_BASEDN
  fi
  if [[ -z "${KS_LDAP_GROUP_SEARCH_BASEDN}" ]]; then
    unset LDAP_GROUP_SEARCH_BASEDN
    while [ -z ${LDAP_GROUP_SEARCH_BASEDN} ]; do
      read -rp "Enter the LDAP GROUP SEARCH BASEDN: " LDAP_GROUP_SEARCH_BASEDN
    done
  else
    LDAP_GROUP_SEARCH_BASEDN=$KS_LDAP_GROUP_SEARCH_BASEDN
  fi
  if [[ -z "${KS_LDAP_READER_GROUP_DN}" ]]; then
    unset LDAP_READER_GROUP_DN
    while [ -z $LDAP_READER_GROUP_DN ]; do
      read -rp "Enter the LDAP GROUP for reader role: " LDAP_READER_GROUP_DN
    done
  else
    LDAP_READER_GROUP_DN=$KS_LDAP_READER_GROUP_DN
  fi
  if [[ -z "${KS_LDAP_AUDITOR_GROUP_DN}" ]]; then
    unset LDAP_AUDITOR_GROUP_DN
    while [ -z $LDAP_AUDITOR_GROUP_DN ]; do
      read -rp "Enter the LDAP GROUP for auditor role: " LDAP_AUDITOR_GROUP_DN
    done
  else
    LDAP_AUDITOR_GROUP_DN=$KS_LDAP_AUDITOR_GROUP_DN
  fi
  if [[ -z "${KS_LDAP_OPERATOR_GROUP_DN}" ]]; then
    unset LDAP_OPERATOR_GROUP_DN
    while [ -z $LDAP_OPERATOR_GROUP_DN ]; do
      read -rp "Enter the LDAP GROUP for operator role: " LDAP_OPERATOR_GROUP_DN
    done
  else
    LDAP_OPERATOR_GROUP_DN=$KS_LDAP_OPERATOR_GROUP_DN
  fi
  if [[ -z "${KS_LDAP_ADMIN_GROUP_DN}" ]]; then
    unset LDAP_ADMIN_GROUP_DN
    while [ -z ${LDAP_ADMIN_GROUP_DN} ]; do
      read -rp "Enter the LDAP GROUP for admin role: " LDAP_ADMIN_GROUP_DN
    done
  else
    LDAP_ADMIN_GROUP_DN=$KS_LDAP_ADMIN_GROUP_DN
  fi
fi

# get installer root root domain
if [[ -z "${KS_INSTALL_DOMAIN}" ]]; then
  unset DOMAIN
  while [ -z $DOMAIN ]; do
    read -rp "Enter the LCM root domain for the KeyStack [demo.local]: " DOMAIN
  done
else
  DOMAIN=$KS_INSTALL_DOMAIN
fi

# get Nexus domain name
if [[ -z "${KS_NEXUS_NAME}" ]]; then
  unset NEXUS_NAME
  read -rp "Enter the LCM Nexus domain name for the KeyStack [nexus]: " NEXUS_NAME
else
  NEXUS_NAME=$KS_NEXUS_NAME
fi
export NEXUS_NAME=${NEXUS_NAME:-"nexus"}

# get Gitlab domain name
if [[ -z "${KS_GITLAB_NAME}" ]]; then
  unset GITLAB_NAME
  read -rp "Enter the LCM Gitlab domain name for the KeyStack [ks-lcm]: " GITLAB_NAME
else
  GITLAB_NAME=$KS_GITLAB_NAME
fi
export GITLAB_NAME=${GITLAB_NAME:-"ks-lcm"}

# get Vault domain name
if [[ -z "${KS_VAULT_NAME}" ]]; then
  unset VAULT_NAME
  read -rp "Enter the LCM Vault domain name for the KeyStack [vault]: " VAULT_NAME
else
  VAULT_NAME=$KS_VAULT_NAME
fi
export VAULT_NAME=${VAULT_NAME:-"vault"}

# get Netbox domain name
if [[ -z "${KS_NETBOX_NAME}" ]]; then
  unset NETBOX_NAME
  read -rp "Enter the LCM Netbox domain name for the KeyStack [netbox]: " NETBOX_NAME
else
  NETBOX_NAME=$KS_NETBOX_NAME
fi
export NETBOX_NAME=${NETBOX_NAME:-"netbox"}

# get Use Self-signed certificate y/N
if [[ -z "${KS_SELF_SIG}" ]]; then
  unset SELF_SIG
  read -rp "Generate Self-signed certificates for KeyStack LCM services y/n [y]: " SELF_SIG
else
  SELF_SIG=$KS_SELF_SIG
fi
export SELF_SIG=${SELF_SIG:-"y"}

## ask the user if everything is good
printf "\n"
cat <<-END
*** Provided settings: ***
Installer HOME: $INSTALL_HOME
LCM IP: $lcm_ip
KeyStack LCM Root Domain: $DOMAIN
KeyStack LCM Nexus Domain: $NEXUS_NAME.$DOMAIN
KeyStack LCM Gitlab Domain: $GITLAB_NAME.$DOMAIN
KeyStack LCM Vault Domain: $VAULT_NAME.$DOMAIN
KeyStack LCM Netbox Domain: $NETBOX_NAME.$DOMAIN
KeyStack generate Self-signed certificate: $SELF_SIG
-----------------Client artifactory-------------------
Use client artifactory: $CLIENT_NEXUS
Client Artifactory full domain name: $CLIENT_NEXUS_NAME
Client Artifactory user name: $CLIENT_NEXUS_ADMIN
Client Artifactory password: $CLIENT_NEXUS_PASSWORD
-----------------LDAP Configs-------------------------
Enable auth LDAP for Netbox and Gitlab: $LDAP_USE
LDAP Server URI: $LDAP_SERVER_URI
LDAP BIND DN: $LDAP_BIND_DN
LDAP BIND Password: $LDAP_BIND_PASSWORD
LDAP USER SEARCH BASEDN: $LDAP_USER_SEARCH_BASEDN
LDAP GROUP SEARCH BASEDN: $LDAP_GROUP_SEARCH_BASEDN
LDAP GROUP for reader role: $LDAP_READER_GROUP_DN
LDAP GROUP for auditor role: $LDAP_AUDITOR_GROUP_DN
LDAP GROUP for operator role: $LDAP_OPERATOR_GROUP_DN
LDAP GROUP for admin role: $LDAP_ADMIN_GROUP_DN

END

if [[ -z "${KS_INSTALL_SILENT}" ]]; then
  echo
  echo "Does it look good?"
  read -n1 -srp "Press any key to continue or CTRL+C to break "
  echo
  echo "Awesome! Proceeding with the installation..."
  echo
fi

## credentials Nexus: Fix to me!
if [[ $CLIENT_NEXUS == "y" ]]; then
  NEXUS_FQDN=$CLIENT_NEXUS_NAME
  NEXUS_USER=$CLIENT_NEXUS_ADMIN
  NEXUS_PASSWORD=$CLIENT_NEXUS_PASSWORD
else
  NEXUS_FQDN=$NEXUS_NAME.$DOMAIN
  NEXUS_USER=admin
  NEXUS_PASSWORD=cdf9f167-f60e-4360-88d5-84e45fa02a99
fi
##

###########################
# * General preparation * #
###########################

INSTALL_DIR=`pwd`

export RELEASE=$RELEASE-$BASE
export LCM_IP=$lcm_ip
export DOMAIN=$DOMAIN
export GITLAB_NAME=$GITLAB_NAME
export VAULT_NAME=$VAULT_NAME
export NETBOX_NAME=$NETBOX_NAME
export NEXUS_NAME=$NEXUS_NAME
export NEXUS_FQDN=$NEXUS_FQDN
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
export CURL_CA_BUNDLE=$CA_HOME/cert/chain-ca.pem

# save settings
cat >./settings <<-END
export RELEASE=$RELEASE
export LCM_IP=$LCM_IP
export DOMAIN=$DOMAIN
export GITLAB_NAME=$GITLAB_NAME
export VAULT_NAME=$VAULT_NAME
export NETBOX_NAME=$NETBOX_NAME
export NEXUS_NAME=$NEXUS_NAME
export NEXUS_FQDN=$NEXUS_FQDN
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
export CURL_CA_BUNDLE=$CURL_CA_BUNDLE
END

mkdir -p $CFG_HOME $REPO_HOME $BACKUP_HOME $VAULT_HOME $NEXUS_HOME $NETBOX_HOME $UPDATE_HOME
cp settings $CFG_HOME
cp version $CFG_HOME
cp compose.yaml $CFG_HOME/

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
  [[ ! -f certs/$NEXUS_FQDN.pem ]] && echo "Chain certificates for $NEXUS_FQDN not found in certs" && exit 1
  cp certs/$NEXUS_FQDN.pem $CA_HOME/cert/$NEXUS_FQDN.pem
fi

if [[ $LDAP_USE == "y" ]]; then
  [[ ! -f certs/ldaps.pem ]] && echo "Chain certificates for LDAPs not found in certs" && exit 1
  cp certs/ldaps.pem $CA_HOME/cert/ldaps.pem
fi

#######################
# * GitLab & Runner * #
#######################

mkdir -p $GITLAB_HOME/{data,logs,config/trusted-certs}
mkdir -p $GITLAB_RUNNER_HOME/{certs,builds,cache}
cp $CA_HOME/cert/chain-$GITLAB_NAME.pem $GITLAB_RUNNER_HOME/certs/$GITLAB_NAME.$DOMAIN.crt
cp $CA_HOME/cert/chain-ca.pem $GITLAB_RUNNER_HOME/certs/ca.crt
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp $CA_HOME/cert/$NEXUS_FQDN.pem $GITLAB_RUNNER_HOME/certs/$NEXUS_FQDN.crt
fi
cp config-template.toml $GITLAB_RUNNER_HOME
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" $GITLAB_RUNNER_HOME/config-template.toml
sed -i "s/RELEASE/$RELEASE/g" $GITLAB_RUNNER_HOME/config-template.toml
sed -i "s|GITLAB_RUNNER_HOME|$GITLAB_RUNNER_HOME|g" $GITLAB_RUNNER_HOME/config-template.toml
openssl rand -base64 20 > $CFG_HOME/gitlab_runner_token
ssh-keygen -qt rsa -b 2048 -N "" -f $CFG_HOME/gitlab_key -C "root@gitlab"
if [[ $LDAP_USE == "y" ]]; then
  cp certs/ldaps.pem /$GITLAB_HOME/config/trusted-certs/ldaps.pem
  cat certs/ldaps.pem >> $GITLAB_RUNNER_HOME/certs/ca.crt
  sed -i "s|LDAP_USE|true|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-BIND-PASSWORD|$LDAP_BIND_PASSWORD|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-READER-GROUP-DN|$LDAP_READER_GROUP_DN|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-AUDITOR-GROUP-DN|$LDAP_AUDITOR_GROUP_DN|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-OPERATOR-GROUP|$LDAP_OPERATOR_GROUP_DN|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-ADMIN-GROUP-DN|$LDAP_ADMIN_GROUP_DN|" $CFG_HOME/compose.yaml
else
  sed -i "s|LDAP_USE|false|" $CFG_HOME/compose.yaml
fi


##############
# * Netbox * #
##############
mkdir -p $NETBOX_HOME/{postgres,redis,redis-cache} $NETBOX_HOME/netbox/{configuration,media,reports,scripts}
cp netbox-docker/docker-compose.yml $CFG_HOME/netbox-compose.yml
cp -r netbox-docker/env $NETBOX_HOME
cp -r netbox-docker/configuration $NETBOX_HOME/netbox
cp netbox-docker/netbox.dump $CFG_HOME/netbox.dump
netbox_admin_password=$(grep SUPERUSER_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
netbox_db_password=$(grep DB_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
netbox_redis_password=$(grep REDIS_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
netbox_redis_cache_password=$(grep REDIS_CACHE_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
# Netbox LDAP settings
if [[ $LDAP_USE == "y" ]]; then
  sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-BIND-PASSWORD|$LDAP_BIND_PASSWORD|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-GROUP-SEARCH-BASEDN|$LDAP_GROUP_SEARCH_BASEDN|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-READER-GROUP-DN|$LDAP_READER_GROUP_DN|g" $NETBOX_HOME/netbox/configuration/ldap/extra.py
  sed -i "s|LDAP-AUDITOR-GROUP-DN|$LDAP_AUDITOR_GROUP_DN|" $NETBOX_HOME/netbox/configuration/ldap/extra.py
  sed -i "s|LDAP-OPERATOR-GROUP-DN|$LDAP_OPERATOR_GROUP_DN|" $NETBOX_HOME/netbox/configuration/ldap/extra.py
  sed -i "s|LDAP-ADMIN-GROUP-DN|$LDAP_ADMIN_GROUP_DN|" $NETBOX_HOME/netbox/configuration/ldap/extra.py
  cp certs/ldaps.pem $NETBOX_HOME/netbox/configuration/ldaps.pem
fi


########################
# * Sonatype Nexus 3 * #
########################
mkdir -p $NEXUS_HOME/{data,blobs,restore-from-backup}
mkdir -p /etc/containers/certs.d/$NEXUS_FQDN
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp $CA_HOME/cert/$NEXUS_FQDN.pem /etc/containers/certs.d/$NEXUS_FQDN/$NEXUS_FQDN.crt
  cat $CA_HOME/cert/$NEXUS_FQDN.pem >> $CA_HOME/cert/chain-ca.pem
else
  cp $CA_HOME/cert/chain-ca.pem /etc/containers/certs.d/$NEXUS_FQDN/ca.crt
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
if [ "$os" == "ubuntu" ] && [ -f lcmpackages-$BASE.gz ]; then
  echo "LCM packages exist => untar and install"
  tar -xf lcmpackages-$BASE.gz
  dpkg -i  packages/*.deb
fi

if [ "$os" == "sberlinux" ] && [ -f lcmpackages-$BASE.gz ]; then
  echo "LCM packages exist => untar and install"
  tar -xf lcmpackages-$BASE.gz
  yum install -y packages/*rpm --skip-broken
  systemctl enable podman
  systemctl start podman
fi

if [ -f nexus-$RELEASE.tar ]; then
  echo "Nexus image exist => loading"
  podman-integrity update_each_file /etc/containers
  $DOCKER_COMMAND load -i nexus-$RELEASE.tar
  for image in $(podman images -qa); do podman-integrity update_image $image; done
  $DOCKER_COMMAND tag $ITKEY_REPO_FQDN/project_k/lcm/nexus3:$RELEASE $NEXUS_FQDN/project_k/lcm/nexus3:$RELEASE
fi

if [ -f nginx-$RELEASE.tar ]; then
  echo "Nginx image exist => loading"
  podman-integrity update_each_file /etc/containers
  $DOCKER_COMMAND load -i nginx-$RELEASE.tar
  for image in $(podman images -qa); do podman-integrity update_image $image; done
  $DOCKER_COMMAND tag $ITKEY_REPO_FQDN/project_k/lcm/nginx:$RELEASE $NEXUS_FQDN/project_k/lcm/nginx:$RELEASE
fi

##########################
# * Offline Nexus data * #
##########################
if [ -f keystack-$RELEASE-nexus-blob-offline.tar.gz ]; then
    echo "keystack-$RELEASE-nexus-blob-offline.tar.gz exist"
    cp keystack-$RELEASE-nexus-blob-offline.tar.gz $NEXUS_HOME/data/nexus-blob-offline.tar.gz
  else
    echo "try to download keystack-$RELEASE-nexus-blob-offline.tar.gz"
    curl -L https://$ITKEY_REPO_FQDN/repository/k-install/keystack-$RELEASE-nexus-blob-offline.tar.gz -o $NEXUS_HOME/data/nexus-blob-offline.tar.gz
fi

if [ -f keystack-$RELEASE-nexus-db-offline.tar.gz ]; then
    echo "keystack-$RELEASE-nexus-db-offline.tar.gz exist."
    cp keystack-$RELEASE-nexus-db-offline.tar.gz $NEXUS_HOME/data/nexus-db-offline.tar.gz
  else
    echo "try to download keystack-$RELEASE-nexus-db-offline.tar.gz"
    curl -L https://$ITKEY_REPO_FQDN/repository/k-install/keystack-$RELEASE-nexus-db-offline.tar.gz -o $NEXUS_HOME/data/nexus-db-offline.tar.gz
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

# copy docker auth config
mkdir -p /root/.docker
cp docker_auth.json /root/.docker/config.json
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" /root/.docker/config.json
chmod 600 /root/.docker/config.json
if [[ $CLIENT_NEXUS == "y" ]]; then
  $DOCKER_COMMAND login $NEXUS_FQDN -u $NEXUS_USER -p $NEXUS_PASSWORD
fi

# copy pip.conf
cp pip.conf /etc/pip.conf
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" /etc/pip.conf

# copy daemon.json
cp daemon.json /etc/docker/daemon.json

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

### for fstek

podman-integrity update_each_file /etc/containers

for image in $(podman images -qa); do podman-integrity update_image $image; done

### for fstek

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d nexus
podman-integrity update_each_file /etc/containers
sleep 5
for container in $(podman ps -qa); do podman-integrity update_container $container; done

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d nginx
podman-integrity update_each_file /etc/containers
sleep 5
for container in $(podman ps -qa); do podman-integrity update_container $container; done

$DOCKER_COMMAND restart nexus nginx

# check for nexus readiness
echo -n Waiting for Nexus readiness

while [ "$(curl -isf https://$NEXUS_FQDN/service/rest/v1/status | awk 'NR==1 {print $2}')"  != "200" ];
do
    echo -n .; sleep 5
done

echo .
echo Nexus is Ready!
rm -f $NEXUS_HOME/restore-from-backup/*

# Upload data to Nexus
function upload_nexus {
if [ -f keystack-$RELEASE-nexus-data.tar.gz ]; then
  echo "Nexus data exist => untar and install"
  tar -xf keystack-$RELEASE-nexus-data.tar.gz
  pip install twine --no-index --find-links file:///$INSTALL_DIR/nexus-$BASE/k-pip
  cd nexus-$BASE
  for directory in *; do
    if [[ $directory == "docker-$BASE" ]]; then
      if [[ $BASE == "sberlinux" ]]; then
        for file in $directory/*; do curl -u "$NEXUS_USER:$NEXUS_PASSWORD" --upload-file ./$file "https://$NEXUS_FQDN/repository/$file" ; done
      elif [[ $BASE == "ubuntu" ]]; then
        cd $directory
        for file in *; do curl -u "$NEXUS_USER:$NEXUS_PASSWORD" -H "Content-Type: multipart/form-data" --data-binary "@./$file" "https://$NEXUS_FQDN/repository/$directory/" ; done
        cd -
      fi
    elif [[ $directory == "images" ]]; then
      for file in $directory/*; do curl -u "$NEXUS_USER:$NEXUS_PASSWORD" --upload-file ./$file "https://$NEXUS_FQDN/repository/$file" ; done
    elif [[ $directory == "k-add" ]]; then
      for file in $directory/*; do curl -u "$NEXUS_USER:$NEXUS_PASSWORD" --upload-file ./$file "https://$NEXUS_FQDN/repository/$file" ; done
    elif [[ $directory == "$BASE" ]]; then
      if [[ $BASE == "sberlinux" ]]; then
        for file in $directory/*; do curl -u "$NEXUS_USER:$NEXUS_PASSWORD" --upload-file ./$file "https://$NEXUS_FQDN/repository/$file" ; done
      elif [[ $BASE == "ubuntu" ]]; then
        cd $directory
        for file in *; do curl -u "$NEXUS_USER:$NEXUS_PASSWORD" -H "Content-Type: multipart/form-data" --data-binary "@./$file" "https://$NEXUS_FQDN/repository/$directory/" ; done
        cd -
      fi
    elif [[ $directory == "k-pip" ]]; then
      python3 -m twine upload -u $NEXUS_USER -p $NEXUS_PASSWORD --skip-existing --disable-progress-bar --repository-url https://$NEXUS_FQDN/repository/$directory/ $directory/*
    fi
  done
  cd -
fi
}

upload_nexus &

#Nexus LCM images
function upload_lcm_nexus {
if [ -f keystack-$RELEASE-lcm-images.tar ]; then
  $DOCKER_COMMAND load -i keystack-$RELEASE-lcm-images.tar
  for image in $(cat keystack-$RELEASE-lcm-images.txt); do
    echo $image | sed "s/$ITKEY_REPO_FQDN/$NEXUS_FQDN/" | xargs -I{} $DOCKER_COMMAND tag $image {};
    echo $image | sed "s/$ITKEY_REPO_FQDN/$NEXUS_FQDN/" | xargs -I{} $DOCKER_COMMAND push {};
    echo $image | xargs -I{} $DOCKER_COMMAND image rm -f {};
    $DOCKER_COMMAND images | grep $NEXUS_FQDN | awk '{print $1 ":" $2 }' | grep -v lcm | grep -v kolla-ansible | xargs -I{} $DOCKER_COMMAND image rm -f {};
  done
fi
}

upload_lcm_nexus
### fstek

podman-integrity update_each_file /etc/containers

for image in $(podman images -qa); do podman-integrity update_image $image; done


# starting the services
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d
#podman-integrity update_each_file /etc/containers
#sleep 5
#for container in $(podman ps -qa); do podman-integrity update_container $container && podman-integrity validate_container $container; done

##project_k netbox start
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/netbox-compose.yml up -d
chmod -R a+w $NETBOX_HOME/redis
#podman-integrity update_each_file /etc/containers
#sleep 5
#for container in $(podman ps -qa); do podman-integrity update_container $container && podman-integrity validate_container $container; done

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml restart nginx
#podman-integrity update_each_file /etc/containers
#sleep 5
#for container in $(podman ps -qa); do podman-integrity update_container $container && podman-integrity validate_container $container; done


# check for gitlab readiness
echo -n Waiting for GitLab readiness
while [ "$(curl -sf https://$GITLAB_NAME.$DOMAIN/-/readiness | jq -r .status)"  != "ok" ];
do
  echo -n .; sleep 5
done
echo .
echo GitLab is Ready!

gitlab_root_password=$(podman exec gitlab grep 'Password:' /etc/gitlab/initial_root_password | awk '{print $2}')
if [[ $LDAP_USE == "y" ]]; then
  $DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec gitlab /bin/bash -c 'echo -e "main:\n  password: '\'$LDAP_BIND_PASSWORD\''\n  bind_dn: '\'$LDAP_BIND_DN\''" | gitlab-rake gitlab:ldap:secret:write'
  sed -i "/bind_dn/d" $CFG_HOME/compose.yaml
  sed -i "/password/d" $CFG_HOME/compose.yaml
  $DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml up -d gitlab
  # check for gitlab readiness
  echo -n Waiting for GitLab readiness
  while [ "$(curl -sf https://$GITLAB_NAME.$DOMAIN/-/readiness | jq -r .status)"  != "ok" ];
  do
    echo -n .; sleep 5
  done
  echo .
  echo GitLab is Ready!
fi

#Nexus images
function upload_docker_nexus {
if [ -f keystack-$RELEASE-docker-images.tar ]; then
  $DOCKER_COMMAND load -i keystack-$RELEASE-docker-images.tar
  for image in $(cat keystack-$RELEASE-docker-images.txt); do
    if [[ $image =~ "kolla-ansible" ]]; then
      echo $image | sed "s/$ITKEY_REPO_FQDN/$NEXUS_FQDN/" | sed "s/\-$BASE$//" | xargs -I{} $DOCKER_COMMAND tag $image {};
      echo $image | sed "s/$ITKEY_REPO_FQDN/$NEXUS_FQDN/" | sed "s/\-$BASE$//" | xargs -I{} $DOCKER_COMMAND push {};
      echo $image | xargs -I{} $DOCKER_COMMAND image rm -f {};
    else
      echo $image | sed "s/$ITKEY_REPO_FQDN/$NEXUS_FQDN/" | xargs -I{} $DOCKER_COMMAND tag $image {};
      echo $image | sed "s/$ITKEY_REPO_FQDN/$NEXUS_FQDN/" | xargs -I{} $DOCKER_COMMAND push {};
      echo $image | xargs -I{} $DOCKER_COMMAND image rm -f {};
      $DOCKER_COMMAND images | grep $NEXUS_FQDN | awk '{print $1 ":" $2 }' | grep -v lcm | grep -v kolla-ansible | xargs -I{} $DOCKER_COMMAND image rm -f {};
    fi
  done
fi
}

upload_docker_nexus &

# Vault unseal and add passwords, kv
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault operator init -key-shares=1 -key-threshold=1 > /vault/config/unseal_info"
for key in $($DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault cat /vault/config/unseal_info | grep "Unseal Key" | awk '{print $4}'); do $DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault vault operator unseal $key; done
for key in $($DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault cat /vault/config/unseal_info | grep "Initial Root" | awk '{print $4}'); do $DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault vault login -no-print $key; done
Unseal_Key=$(cat $VAULT_HOME/config/unseal_info | grep "Unseal Key" | awk '{print $4}')
Root_Token=$(cat $VAULT_HOME/config/unseal_info | grep "Initial Root" | awk '{print $4}')

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
pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$gitlab_root_password\"}"
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

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec gitlab /bin/sh -c "echo "UPDATE application_settings SET signup_enabled = false" | gitlab-psql"

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault auth enable approle"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault secrets enable -path=secret_v2 -version 2 kv"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault policy write secret_v2/deployments /vault/config/policy_secret.hcl"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault write auth/approle/role/keystack token_type=batch token_policies=secret_v2/deployments"
role_id=$($DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault read -field=role_id auth/approle/role/keystack/role-id")
secret_id=$($DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault write -f -field=secret_id auth/approle/role/keystack/secret-id")

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/secrets/job_key value=\"$(<$CFG_HOME/gitlab_key)\""
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/secrets/ca.crt value=\"$(<$CA_HOME/cert/chain-ca.pem)\""
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/bifrost/rmi user="itkey" password="r00tme""
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault secrets enable -path installer pki"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault secrets tune -max-lease-ttl=43800h installer"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault write installer/config/ca pem_bundle=@vault/config/root.pem"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault write installer/roles/certs allowed_domains="$DOMAIN" allow_subdomains=true max_ttl=17520h ttl=17520h"
$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault write installer/config/urls issuing_certificates="https://$VAULT_NAME.$DOMAIN/v1/pki/ca"  crl_distribution_points="https://$VAULT_NAME.$DOMAIN/v1/pki/crl""
rm -f $VAULT_HOME/config/root.pem

# Region1 CA configuration
cp $CA_HOME/cert/chain-ca.pem project_k/deployments/region1/certificates/ca/ca-bundle.crt
sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-GROUP-SEARCH-BASEDN|$LDAP_GROUP_SEARCH_BASEDN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-READER-GROUP-DN|$LDAP_READER_GROUP_DN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-AUDITOR-GROUP-DN|$LDAP_AUDITOR_GROUP_DN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-OPERATOR-GROUP|$LDAP_OPERATOR_GROUP_DN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf
sed -i "s|LDAP-ADMIN-GROUP-DN|$LDAP_ADMIN_GROUP_DN|" project_k/services/gitlab-ldap-sync/gitlab-ldap-sync.conf

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
netbox_token=$(curl -X POST -H "Content-Type: application/json" -H "Accept: application/json; indent=4" "https://$NETBOX_NAME.$DOMAIN/api/users/tokens/provision/" --data '{"username": "admin", "password": "'$netbox_admin_password'"}' --insecure | jq .key)
curl -sX PUT -H "Authorization: Bearer $token" -d "visibility=internal" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=GIT_SSL_NO_VERIFY" -F "value=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq


curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY_USER" -F "value=$NEXUS_USER"  "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_REGISTRY" -F "value=$NEXUS_FQDN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=NETBOX_URI" -F "value=http://$NETBOX_NAME.$DOMAIN:8080" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=CI_REGISTRY" -F 'value=$KEYSTACK_REGISTRY' "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=NEXUS_FQDN" -F "value=$NEXUS_FQDN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=KEYSTACK_NEXUS" -F "value=https://$NEXUS_FQDN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=NEXUS_USER" -F "value=$NEXUS_USER" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=LCM_IP" -F "value=$LCM_IP" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=DOMAIN" -F "value=$DOMAIN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=INSTALL_HOME" -F "value=$INSTALL_HOME" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=BASE" -F "value=$BASE" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=ANSIBLE_FORCE_COLOR" -F "value=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/admin/ci/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=ANSIBLE_STDOUT_CALLBACK" -F "value=yaml" "https://$GITLAB_NAME.$DOMAIN/api/v4/admin/ci/variables" | jq

#project_k Vault configuration
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_addr" -F "value=https://$VAULT_NAME.$DOMAIN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_engine" -F "value=secret_v2" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_method" -F "value=approle" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_username" -F "value=$role_id" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_password" -F "value=$secret_id" -F "masked=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_prefix" -F "value=deployments/$GITLAB_NAME.$DOMAIN" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_role" -F "value=keystack" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_pki" -F "value=installer" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_role_pki" -F "value=certs" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq
curl -sX POST -H "Authorization: Bearer $token" -F "key=vault_secman" -F "value=false" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/${group_id_project_k}/variables" | jq

#new changes in gitlab - need to disable scope job token access
ci_prj_id=$(curl -sH "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects?search=ci&simple=true" | jq .[0].id)
curl -sX PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/${ci_prj_id}/job_token_scope"
ci_prj_id=$(curl -sH "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects?search=keystack&simple=true" | jq .[0].id)
curl -sX PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/${ci_prj_id}/job_token_scope"

wait

if [[ $LDAP_USE == "y" ]]; then
  # deploy ldap sync schedule
  function generate_pat() {
    local existing_pat=$(docker exec gitlab gitlab-rails runner "
      user = User.find_by(username: 'root')
      token = user.personal_access_tokens.find_by(name: 'PAT')
      if token
        puts token.id
      end
    ")
    if [ -n "$existing_pat" ]; then
        $DOCKER_COMMAND exec gitlab gitlab-rails runner "
            user = User.find_by(username: 'root')
            token = user.personal_access_tokens.find_by(id: $existing_pat)
            token.destroy if token"
    fi
    PAT=$($DOCKER_COMMAND exec gitlab gitlab-rails runner "
      require 'securerandom'
      user = User.find_by(username: 'root')
      token_plain = SecureRandom.hex(20)
      token = user.personal_access_tokens.create!(
        name: 'PAT',
        scopes: ['api', 'sudo'],
        expires_at: Time.current + 1.year
      )
      token.set_token(token_plain)
      token.save!
      puts token.token"
    )
    if [ -z "$PAT" ]; then
      echo "PAT creation error" && exit 1
    fi
  }

  generate_pat

  function get_project_id() {
    PROJECT_ID=$(curl --silent --header "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects" | jq ".[] | select(.name == \"gitlab-ldap-sync\") | .id")
    if [ -z "$PROJECT_ID" ]; then
      echo "Project services/gitlab-ldap-sync not found" && exit 1
    fi
  }

  get_project_id

  function manage_gitlab_variable() {
    local var_key=$1
    local var_val=$2

    local existing_var=$(curl --silent --header "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/variables" | jq -r ".[] | select(.key == \"$var_key\") | .value // empty")
    if [ -n "$existing_var" ]; then
      curl --silent --request DELETE "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/variables/$var_key" \
        --header "PRIVATE-TOKEN: $PAT"
    fi
    curl --silent --request POST "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/variables" \
      --header "PRIVATE-TOKEN: $PAT" \
      --form key="$var_key" \
      --form value="$var_val"
  }

  manage_gitlab_variable "GITLAB_TOKEN" "$PAT"
  manage_gitlab_variable "LDAP_PASSWORD" "$LDAP_BIND_PASSWORD"

  function create_schedule() {
    local existing_schedule=$(curl --silent --header "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every day at 12AM\") | .id")
    if [ -n "$existing_schedule" ]; then
      curl --silent --request DELETE "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule" \
        --header "PRIVATE-TOKEN: $PAT"
    fi
    curl --request POST --header "PRIVATE-TOKEN: $PAT" \
      --form description="Sync every day at 12AM" \
      --form ref="master" \
      --form cron="0 0 * * *" \
      --form cron_timezone="UTC" \
      --form active="true" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules"
  }

  create_schedule

  trigger_pipeline() {
    local existing_trigger=$(curl --silent --header "PRIVATE-TOKEN: $PAT" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/triggers" | jq -r '.[] | select(.description == "Automated Trigger") | .token')
    if [ -z "$existing_trigger" ]; then
      existing_trigger=$(curl --silent --request POST "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/triggers" \
        --header "PRIVATE-TOKEN: $PAT" \
        --form description="Automated Trigger" | jq -r '.token')
    fi
    curl --silent --request POST "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/trigger/pipeline" \
      --form token="$existing_trigger" \
      --form ref="master"
  }

  trigger_pipeline
fi

# remove unneeded env variables
unset SAN

printf "\n\n\n############################################################\n"
echo "#                YOUR INSTALLATION IS READY                #"
printf "############################################################\n\n\n"

echo LCM GitLab root password: $gitlab_root_password
echo LCM GitLab runner token: $(<$CFG_HOME/gitlab_runner_token)
echo LCM GitLab SSH private key: $CFG_HOME/gitlab_key
echo LCM GitLab SSH public key: $CFG_HOME/gitlab_key.pub
echo LCM Nexus admin password: $NEXUS_PASSWORD
echo LCM Netbox admin password: $netbox_admin_password
echo LCM Netbox postgres password: $netbox_db_password
echo LCM Netbox redis password: $netbox_redis_password
echo LCM Netbox redis cache password: $netbox_redis_cache_password
echo LCM Vault Initial Root Token: $Root_Token
echo LCM Vault Unseal Key 1: $Unseal_Key
echo LCM Root CA Certificate: $CA_HOME/cert/chain-ca.pem

$DOCKER_COMPOSE_COMMAND -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "update-ca-trust && vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/secrets/accounts gitlab_root_password="$gitlab_root_password" gitlab_runner_token=\"$(<$CFG_HOME/gitlab_runner_token)\" nexus_admin_password="$NEXUS_PASSWORD" netbox_admin_password="$netbox_admin_password" netbox_db_password="$netbox_db_password" netbox_redis_password="$netbox_redis_password" netbox_redis_cache_password="$netbox_redis_cache_password" NETBOX_TOKEN="$netbox_token""

rm -f $VAULT_HOME/config/unseal_info
rm -f $VAULT_HOME/config/root.pem
rm -f $GITLAB_HOME/config/initial_root_password
echo "" > netbox-docker/env/postgres.env
echo "" > netbox-docker/env/redis-cache.env
echo "" > netbox-docker/env/netbox.env
echo "" > netbox-docker/env/redis.env

echo "gitlab_runner_token" > $CFG_HOME/gitlab_runner_token
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=netbox_db_password|" $NETBOX_HOME/env/netbox.env
sed -i "s|REDIS_CACHE_PASSWORD=.*|REDIS_CACHE_PASSWORD=netbox_redis_cache_password|" $NETBOX_HOME/env/netbox.env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=netbox_redis_password|" $NETBOX_HOME/env/netbox.env
sed -i "s|SUPERUSER_PASSWORD=.*|SUPERUSER_PASSWORD=netbox_admin_password|" $NETBOX_HOME/env/netbox.env
sed -i "s|AUTH_LDAP_BIND_PASSWORD: .*|AUTH_LDAP_BIND_PASSWORD: \"LDAP-BIND-PASSWORD\"|" $NETBOX_HOME/env/netbox.env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=netbox_db_password|" $NETBOX_HOME/env/postgres.env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=netbox_redis_password|" $NETBOX_HOME/env/redis.env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=netbox_redis_cache_password|" $NETBOX_HOME/env/redis-cache.env

