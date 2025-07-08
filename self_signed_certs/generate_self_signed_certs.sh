#!/bin/bash
set -x

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
script_name=$(basename "$0")
env_file="certs_envs"
green=`tput setaf 2`
yellow=`tput setaf 3`
normal=`tput sgr0`
ldaps_crt=ldaps.pem

while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
    The script generate selfsigned wildcard from domain
    To generate selfsigned certificates:
        1) Edit env list: $HOME/test_scripts_keystack/self_signed_certs/$env_file
        2) Start script: $HOME/test_scripts_keystack/self_signed_certs/$script_name
    "
      exit 0
      break ;;
    --) shift
      break ;;
    *) echo "$1 is not an option";;
  esac
  shift
done

# Define parameters
count=1
for param in "$@"; do
  echo "Parameter #$count: $param"
  count=$(( $count + 1 ))
done


yes_no_answer () {
  yes_no_input=""
  while true; do
    read -p "$yes_no_question" yn
    yn=${yn:-"Yes"}
    echo $yn
    case $yn in
        [Yy]* ) yes_no_input="true"; break;;
        [Nn]* ) yes_no_input="false"; break ;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  yes_no_question="<Empty yes\no question>"
}

get_init_vars () {

  echo "Get init variables"
  echo "Try to source $script_dir/$env_file"

  if [ -f $script_dir/$env_file ]; then
    source $script_dir/$env_file
  else
    echo -e "${yellow}Env file $script_dir/$env_file not exists"
  fi

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
  if [[ -z "${REGION}" ]]; then
    read -rp "Enter region name [ebochkov]: " REGION
  fi
  export REGION=${REGION:-"ebochkov"}

  # get internal fqdn name
  if [[ -z "${INTERNAL_FQDN}" ]]; then
    read -rp "Enter internal FQDN [internal.$REGION.$DOMAIN]: " INTERNAL_FQDN
  fi
  export INTERNAL_FQDN=${INTERNAL_FQDN:-"internal.$REGION.$DOMAIN"}

  # get internal VIP name
  if [[ -z "${INTERNAL_VIP}" ]]; then
    read -rp "Enter internal VIP: " INTERNAL_VIP
  fi
  export INTERNAL_VIP=${INTERNAL_VIP}

  # get external fqdn name
  if [[ -z "${EXTERNAL_FQDN}" ]]; then
    read -rp "Enter external FQDN [external.$REGION.$DOMAIN]: " EXTERNAL_FQDN
  fi
  export EXTERNAL_FQDN=${EXTERNAL_FQDN:-"external.$REGION.$DOMAIN"}

  # get external VIP name
  if [[ -z "${EXTERNAL_VIP}" ]]; then
    read -rp "Enter external VIP: " EXTERNAL_VIP
  fi
  export EXTERNAL_VIP=${EXTERNAL_VIP}

  # get CA_IP name
  if [[ -z "${CA_IP}" ]]; then
    read -rp "Enter IP Central Authentication Service [192.168.0.55]: " CA_IP
  fi
  export CA_IP=${CA_IP:-"192.168.0.55"}

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

  echo -E "
    CERTS_DIR:          $CERTS_DIR
    OUTPUT_CERTS_DIR:   $OUTPUT_CERTS_DIR
    DOMAIN:             $DOMAIN
    REGION:             $REGION
    INTERNAL_FQDN:      $INTERNAL_FQDN
    INTERNAL_VIP:       $INTERNAL_VIP
    EXTERNAL_FQDN:      $EXTERNAL_FQDN
    EXTERNAL_VIP:       $EXTERNAL_VIP
    CA_IP:              $CA_IP
    LCM_NEXUS_NAME:     $LCM_NEXUS_NAME
    REMOTE_NEXUS_NAME:  $REMOTE_NEXUS_NAME
    LCM_GITLAB_NAME:    $LCM_GITLAB_NAME
    LCM_VAULT_NAME:     $LCM_VAULT_NAME
    LCM_NETBOX_NAME:    $LCM_NETBOX_NAME
  "

#  read -p "Press enter to continue: "

  #Export envs...
  cat > $script_dir/.certs_envs <<-END
  export CERTS_DIR=$CERTS_DIR
  export OUTPUT_CERTS_DIR=$OUTPUT_CERTS_DIR
  export DOMAIN=$DOMAIN
  export REGION=$REGION
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
}

#Checking if directory $CERTS_DIR and $OUTPUT_CERTS_DIR are empty
check_certs_folder_empty () {
  echo "Checking if directory $CERTS_DIR and $OUTPUT_CERTS_DIR are empty..."
  if [ -z "$( ls -A $CERTS_DIR/certs )" ] && [ -z "$( ls -A $CERTS_DIR/root )" ] && \
   [ -z "$( ls -A "$OUTPUT_CERTS_DIR" )" ]; then
     printf "%s\n" "${green}Directory $CERTS_DIR and $OUTPUT_CERTS_DIR are empty - ok${normal}"
  else
     printf "%s\n" "${yellow}Directory $CERTS_DIR and $OUTPUT_CERTS_DIR are not empty!${normal}"
  fi
}

generate_ca_certs () {
  echo "generate ca certs..."
  if [ ! -f $CERTS_DIR/root/ca.key ] && [ ! -f $CERTS_DIR/root/ca.crt ] && [ ! -f $CERTS_DIR/certs/cert.csr ] \
    && [ ! -f $CERTS_DIR/certs/cert.crt ];then

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

    export SAN=DNS:$REGION.$DOMAIN,DNS:*$REGION.$DOMAIN,IP:$CA_IP

    openssl x509 -req -in $CERTS_DIR/certs/cert.csr \
      -extfile $script_dir/cert.cnf -CA $CERTS_DIR/root/ca.crt \
      -CAkey $CERTS_DIR/root/ca.key -CAcreateserial \
      -out $CERTS_DIR/certs/cert.crt -days 728 -sha256

#    #external internal pem
#    cat $CERTS_DIR/certs/external_VIP.crt $CERTS_DIR/certs/cert.key > $CERTS_DIR/certs/haproxy_pem
#    cat $CERTS_DIR/certs/internal_VIP.crt $CERTS_DIR/certs/cert.key > $CERTS_DIR/certs/haproxy_internal_pem
#    cp $CERTS_DIR/certs/haproxy_pem $OUTPUT_CERTS_DIR/haproxy_pem
#    cp $CERTS_DIR/certs/haproxy_internal_pem $OUTPUT_CERTS_DIR/haproxy_internal_pem

#    #backend_pem
#    cp $CERTS_DIR/certs/backend.crt $OUTPUT_CERTS_DIR/backend_pem
#    cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/backend_key_pem
  else
    printf "%s\n" "${yellow}$CERTS_DIR/root/ca.key, $CERTS_DIR/root/ca.crt, $CERTS_DIR/certs/cert.csr, $CERTS_DIR/certs/cert.crt \
already exists${normal}"
  fi
}

generate_internal_cert () {
  echo "Generate internal cert..."
  if [ ! -f $CERTS_DIR/certs/internal_VIP.csr ] && [ ! -f $CERTS_DIR/certs/internal_VIP.crt ]; then

    openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=$INTERNAL_FQDN" \
      -key $CERTS_DIR/certs/cert.key \
      -out $CERTS_DIR/certs/internal_VIP.csr
    export SAN=DNS:$INTERNAL_FQDN,IP:$INTERNAL_VIP
    openssl x509 -req -in $CERTS_DIR/certs/internal_VIP.csr \
      -extfile $script_dir/cert.cnf -CA $CERTS_DIR/root/ca.crt \
      -CAkey $CERTS_DIR/root/ca.key -CAcreateserial \
      -out $CERTS_DIR/certs/internal_VIP.crt -days 728 -sha256

    cat $CERTS_DIR/certs/internal_VIP.crt $CERTS_DIR/certs/cert.key > $CERTS_DIR/certs/haproxy_internal_pem
    cp $CERTS_DIR/certs/haproxy_internal_pem $OUTPUT_CERTS_DIR/haproxy_internal_pem
    echo "Internal cert was created"
  else
    printf "%s\n" "${yellow}$CERTS_DIR/certs/internal_VIP.csr, $CERTS_DIR/certs/internal_VIP.crt already exists${normal}"
  fi
}

generate_external_cert () {
  echo "Generate external cert..."
  if [ ! -f $CERTS_DIR/certs/external_VIP.csr ] && [ ! -f $CERTS_DIR/certs/external_VIP.crt ]; then

    openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=$EXTERNAL_FQDN" \
      -key $CERTS_DIR/certs/cert.key \
      -out $CERTS_DIR/certs/external_VIP.csr
    export SAN=DNS:$EXTERNAL_FQDN,IP:$EXTERNAL_VIP
    openssl x509 -req -in $CERTS_DIR/certs/external_VIP.csr \
      -extfile $script_dir/cert.cnf -CA $CERTS_DIR/root/ca.crt \
      -CAkey $CERTS_DIR/root/ca.key -CAcreateserial \
      -out $CERTS_DIR/certs/external_VIP.crt -days 728 -sha256
    #external internal pem

    cat $CERTS_DIR/certs/external_VIP.crt $CERTS_DIR/certs/cert.key > $CERTS_DIR/certs/haproxy_pem
    cp $CERTS_DIR/certs/haproxy_pem $OUTPUT_CERTS_DIR/haproxy_pem
    echo "External cert was created"
  else
    printf "%s\n" "${yellow}$CERTS_DIR/certs/external_VIP.csr, $CERTS_DIR/certs/external_VIP.crt already exists${normal}"
  fi
}

generate_backend_cert () {
  echo "Generate backend cert..."
  if [ ! -f $CERTS_DIR/certs/backend.csr ] && [ ! -f $CERTS_DIR/certs/backend.crt ]; then

    openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=backend.$EXTERNAL_FQDN" \
      -key $CERTS_DIR/certs/cert.key \
      -out $CERTS_DIR/certs/backend.csr
    # required controls IPs
    export SAN=IP:$EXTERNAL_VIP,IP:$INTERNAL_VIP
    openssl x509 -req -in $CERTS_DIR/certs/backend.csr \
      -extfile $script_dir/cert.cnf \
      -CA $CERTS_DIR/root/ca.crt \
      -CAkey $CERTS_DIR/root/ca.key \
      -CAcreateserial -out $CERTS_DIR/certs/backend.crt -days 728 -sha256

    cp $CERTS_DIR/certs/backend.crt $OUTPUT_CERTS_DIR/backend_pem
    cp $CERTS_DIR/certs/cert.key $OUTPUT_CERTS_DIR/backend_key_pem
    echo "Backend cert was created"
  else
    printf "%s\n" "${yellow}$CERTS_DIR/certs/backend.csr, $CERTS_DIR/certs/backend.crt already exists${normal}"
  fi
}

generate_certs () {

  mkdir -p $CERTS_DIR/{root,certs}
  mkdir -p $OUTPUT_CERTS_DIR

  check_certs_folder_empty

  yes_no_question="Do you want to Generating certs? [Yes]: "
  yes_no_answer

  if [ "$yes_no_input" = "true" ]; then
    echo "Generating certificates..."

    generate_ca_certs
    generate_internal_cert
    generate_external_cert
    generate_backend_cert

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
    cp $script_dir/$ldaps_crt $OUTPUT_CERTS_DIR/$ldaps_crt
  else
    printf "%s\n" "${yellow}No self-signed certificates were created!${normal}"
    exit 0
  fi
}

get_init_vars
generate_certs
ls -la $OUTPUT_CERTS_DIR
