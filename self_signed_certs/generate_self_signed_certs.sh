#!/bin/bash

# The script generate selfsigned wildcard from domain
# env list:
#   CERTS_DIR: $HOME/central_auth_service
#   OUTPUT_CERTS_DIR: $HOME/certs
#   DOMAIN: test.domain
#   CA_IP: 10.224.129.234 # any ip
#   LCM_NEXUS_NAME: lcm-nexus
#   LCM_GITLAB_NAME: lcm-gitlab
#   LCM_VAULT_NAME: lcm-vault
#   LCM_NETBOX_NAME: lcm-netbox

# !!! to start:
# source $HOME/test_scripts_keystack/self_signed_certs/certs_envs
# bash $HOME/test_scripts_keystack/self_signed_certs/generate_self_signed_certs.sh
# After generate $HOME/certs will be created

# Hand made generate example for installer.sh
#openssl genrsa -out ext_vip.key 2048
#openssl x509 -req -in ./external_VIP.csr -extfile /root/installer/cert.cnf -CA /installer/data/ca/root/ca.crt -CAkey /installer/data/ca/root/ca.key -CAcreateserial -out ./external_VIP.crt -days 728 -sha256
#export SAN=DNS:ext.ebochkov.test.domain,IP:10.224.129.228
#openssl x509 -req -in ./external_VIP.csr \
#  -extfile /root/installer/cert.cnf \
#  -CA /installer/data/ca/root/ca.crt \
#  -CAkey /installer/data/ca/root/ca.key \
#  -CAcreateserial -out ./external_VIP.crt -days 728 -sha256

script_dir=$(dirname $0)
yellow=`tput setaf 3`
reset=`tput sgr0`



generate_certs () {

echo "Generating certification..."
# get Central Authentication Service folder
if [[ -z "${CERTS_DIR}" ]]; then
  read -rp "Enter Central Authentication Service folder [$HOME/central_auth_service]: " CERTS_DIR
fi
export CERTS_DIR=${CERTS_DIR:-"$HOME/central_auth_service"}

# get Output certs folder
if [[ -z "${OUTPUT_CERTS_DIR}" ]]; then
  read -rp "Enter certs output folder for installer [$HOME/certs]: " OUTPUT_CERTS_DIR
fi
export OUTPUT_CERTS_DIR=${OUTPUT_CERTS_DIR:-"$HOME/certs"}

# get domain name
if [[ -z "${DOMAIN}" ]]; then
  read -rp "Enter certs output folder for installer [test.domain]: " DOMAIN
fi
export DOMAIN=${DOMAIN:-"test.domain"}

# get region name
if [[ -z "${REGION_NAME}" ]]; then
  read -rp "Enter region name [ebochkov]: " REGION_NAME
fi
export REGION_NAME=${REGION_NAME:-"ebochkov"}

# get internal fqdn name
if [[ -z "${INTERNAL_FQDN}" ]]; then
  read -rp "Enter internal FQDN [int.$REGION_NAME.$DOMAIN]: " INTERNAL_FQDN
fi
export INTERNAL_FQDN=${INTERNAL_FQDN:-"int.$REGION_NAME.$DOMAIN"}

# get internal VIP name
if [[ -z "${INTERNAL_VIP}" ]]; then
  read -rp "Enter internal VIP: " INTERNAL_VIP
fi
export INTERNAL_VIP=${INTERNAL_VIP}

# get external fqdn name
if [[ -z "${EXTERNAL_FQDN}" ]]; then
  read -rp "Enter external FQDN [ext.$REGION_NAME.$DOMAIN]: " EXTERNAL_FQDN
fi
export EXTERNAL_FQDN=${EXTERNAL_FQDN:-"ext.$REGION_NAME.$DOMAIN"}

# get external VIP name
if [[ -z "${EXTERNAL_VIP}" ]]; then
  read -rp "Enter external VIP: " EXTERNAL_VIP
fi
export EXTERNAL_VIP=${EXTERNAL_VIP}

# get CA_IP name
if [[ -z "${CA_IP}" ]]; then
  read -rp "Enter IP Central Authentication Service [10.224.129.234]: " CA_IP
fi
export CA_IP=${CA_IP:-"10.224.129.234"}

# get Nexus domain name
if [[ -z "${LCM_NEXUS_NAME}" ]]; then
  read -rp "Enter the LCM Nexus domain name [lcm-nexus]: " LCM_NEXUS_NAME
fi
export LCM_NEXUS_NAME=${LCM_NEXUS_NAME:-"lcm-nexus"}

# get Remote Nexus domain nama
if [[ -z "${REMOTE_NEXUS_NAME}" ]]; then
  read -rp "Enter the Remote Nexus domain name [remote-nexus]: " REMOTE_NEXUS_NAME
fi
export REMOTE_NEXUS_NAME=${REMOTE_NEXUS_NAME:-"remote-nexus"}

# get Gitlab domain name
if [[ -z "${LCM_GITLAB_NAME}" ]]; then
  read -rp "Enter the LCM Gitlab domain name [gitlab]: " LCM_GITLAB_NAME
fi
export LCM_GITLAB_NAME=${LCM_GITLAB_NAME:-"gitlab"}

# get Vault domain name
if [[ -z "${LCM_VAULT_NAME}" ]]; then
  read -rp "Enter the LCM Vault domain name [vault]: " LCM_VAULT_NAME
fi
export LCM_VAULT_NAME=${LCM_VAULT_NAME:-"vault"}

# get Netbox domain name
if [[ -z "${LCM_NETBOX_NAME}" ]]; then
  read -rp "Enter the LCM Netbox domain name [netbox]: " LCM_NETBOX_NAME
fi
export LCM_NETBOX_NAME=${LCM_NETBOX_NAME:-"netbox"}

if [[ -z "${INTERNAL_VIP}" ]] || [[ -z "${EXTERNAL_VIP}" ]]; then
  echo "internal VIP or external VIP not define"
  exit 1
fi

#Export envs...
cat > $script_dir/certs_envs <<-END
export CERTS_DIR=$CERTS_DIR
export OUTPUT_CERTS_DIR=$OUTPUT_CERTS_DIR
export DOMAIN=$DOMAIN
export REGION_NAME=$REGION_NAME
export INTERNAL_FQDN=$INTERNAL_FQDN
export INTERNAL_VIP=$INTERNAL_VIP
export EXTERNAL_FQDN=$EXTERNAL_FQDN
export EXTERNAL_VIP=$EXTERNAL_VIP
export CA_IP=$CA_IP
export LCM_NEXUS_NAME=$LCM_NEXUS_NAME
export REMOTE_NEXUS_NAME=$REMOTE_NEXUS_NAME
export LCM_GITLAB_NAME=$LCM_GITLAB_NAME
export LCM_VAULT_NAME=$LCM_VAULT_NAME
export LCM_NETBOX_NAME=$LCM_NETBOX_NAME
END



# Create Wildcard
mkdir -p $CERTS_DIR/{root,certs}
mkdir -p $OUTPUT_CERTS_DIR

openssl genrsa -out $CERTS_DIR/root/ca.key 2048
chmod 400 $CERTS_DIR/root/ca.key

openssl req -new -x509 -nodes -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=KeyStack Root CA" \
        -key $CERTS_DIR/root/ca.key -sha256 \
        -days 3650 -out $CERTS_DIR/root/ca.crt
chmod 444 $CERTS_DIR/root/ca.crt

openssl genrsa -out $CERTS_DIR/certs/cert.key 2048
chmod 400 $CERTS_DIR/certs/cert.key

openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=*.$DOMAIN" \
        -key $CERTS_DIR/certs/cert.key -out $CERTS_DIR/certs/cert.csr

export SAN=DNS:$DOMAIN,DNS:*.$DOMAIN,IP:$CA_IP

openssl x509 -req -in $CERTS_DIR/certs/cert.csr \
        -extfile $script_dir/cert.cnf -CA $CERTS_DIR/root/ca.crt \
        -CAkey $CERTS_DIR/root/ca.key -CAcreateserial \
        -out $CERTS_DIR/certs/cert.crt -days 728 -sha256

#===========
#internal cert
openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=$INTERNAL_FQDN" \
  -key $CERTS_DIR/certs/cert.key \
  -out $CERTS_DIR/certs/external_VIP.csr
export SAN=DNS:$INTERNAL_FQDN,IP:$INTERNAL_VIP
openssl x509 -req -in $CERTS_DIR/certs/external_VIP.csr \
        -extfile $script_dir/cert.cnf -CA $CERTS_DIR/root/ca.crt \
        -CAkey $CERTS_DIR/root/ca.key -CAcreateserial \
        -out $CERTS_DIR/certs/external_VIP.crt -days 728 -sha256
#===========
#external cert
openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=$EXTERNAL_FQDN" \
  -key $CERTS_DIR/certs/cert.key \
  -out $CERTS_DIR/certs/external_VIP.csr
export SAN=DNS:$EXTERNAL_FQDN,IP:$EXTERNAL_VIP
#openssl x509 -req -in $CERTS_DIR/certs/external_VIP.csr -extfile $HOME/test_scripts_keystack/self_signed_certs/cert.cnf -CA $HOME/central_auth_service/root/ca.crt -CAkey $HOME/central_auth_service/root/ca.key -CAcreateserial -out $HOME/certs/external_VIP.crt -days 728 -sha256
openssl x509 -req -in $CERTS_DIR/certs/external_VIP.csr \
        -extfile $script_dir/cert.cnf -CA $CERTS_DIR/root/ca.crt \
        -CAkey $CERTS_DIR/root/ca.key -CAcreateserial \
        -out $CERTS_DIR/certs/external_VIP.crt -days 728 -sha256
#===========

cat $CERTS_DIR/certs/cert.crt $CERTS_DIR/root/ca.crt > $CERTS_DIR/certs/chain-ca.pem

# Copying certs to certs output folder for installer
cp $CERTS_DIR/root/ca.crt $OUTPUT_CERTS_DIR;
# for remote nexus
cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/cert.key;
cp $CERTS_DIR/certs/chain-ca.pem $OUTPUT_CERTS_DIR/$LCM_NEXUS_NAME.$DOMAIN.pem;
cp $CERTS_DIR/certs/chain-ca.pem $OUTPUT_CERTS_DIR/$REMOTE_NEXUS_NAME.$DOMAIN.pem;

cp $CERTS_DIR/certs/chain-ca.pem $OUTPUT_CERTS_DIR;

cp $CERTS_DIR/certs/cert.crt $OUTPUT_CERTS_DIR/$LCM_NEXUS_NAME.crt;
cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/$LCM_NEXUS_NAME.key;
cp $CERTS_DIR/certs/cert.crt $OUTPUT_CERTS_DIR/$LCM_GITLAB_NAME.crt;
cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/$LCM_GITLAB_NAME.key;
cp $CERTS_DIR/certs/cert.crt $OUTPUT_CERTS_DIR/$LCM_VAULT_NAME.crt;
cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/$LCM_VAULT_NAME.key;
cp $CERTS_DIR/certs/cert.crt $OUTPUT_CERTS_DIR/$LCM_NETBOX_NAME.crt;
cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/$LCM_NETBOX_NAME.key

#external internal pem
cat $CERTS_DIR/certs/external_VIP.crt $CERTS_DIR/root/ca.crt > $CERTS_DIR/certs/haproxy_pem
cat $CERTS_DIR/certs/internal_VIP.crt $CERTS_DIR/root/ca.crt > $CERTS_DIR/certs/internal_haproxy_pem
cp $CERTS_DIR/certs/haproxy_pem $OUTPUT_CERTS_DIR/haproxy_pem
cp $CERTS_DIR/certs/internal_haproxy_pem $OUTPUT_CERTS_DIR/internal_haproxy_pem
}

while true; do
  read -p "Do you want to Generating certs? [Yes]: " yn
  yn=${yn:-"Yes"}
  echo $yn
  case $yn in
    [Yy]* ) yes_no_input="true"; break;;
    [Nn]* ) yes_no_input="false"; break ;;
    * ) echo "Please answer yes or no.";;
  esac
done

if [ "$yes_no_input" = "true" ]; then
  source $script_dir/certs_envs
  echo -E "
  env list:
  CERTS_DIR:        $CERTS_DIR
  OUTPUT_CERTS_DIR: $OUTPUT_CERTS_DIR
  DOMAIN:           $DOMAIN
  REGION_NAME:      $REGION_NAME
  INTERNAL_FQDN:    $INTERNAL_FQDN
  INTERNAL_VIP:     $INTERNAL_VIP
  EXTERNAL_FQDN:    $EXTERNAL_FQDN
  EXTERNAL_VIP:     $EXTERNAL_VIP
  CA_IP: $CA_IP
  LCM_NEXUS_NAME: $LCM_NEXUS_NAME
  REMOTE_NEXUS_NAME: $REMOTE_NEXUS_NAME
  LCM_GITLAB_NAME: $LCM_GITLAB_NAME
  LCM_VAULT_NAME: $LCM_VAULT_NAME
  LCM_NETBOX_NAME: $LCM_NETBOX_NAME
"
  generate_certs
else
  echo "Nexus cannot be deployed without certificates"
  exit 1
fi
