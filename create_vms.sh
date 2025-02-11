#!/bin/bash

#The script accepts the following environment variables
#for example:

#cat >./source_vm_create <<-END
#export OPENRC_PATH="/installer/config/openrc"
#export VM_QTY="1"
#export IMAGE="ubuntu-20.04-x64"
#export FLAVOR="4c-4r"
#export KEY_NAME="key1"
#export HYPERVISOR_HOSTNAME="cmpt-3"
#export API_VERSION="2.74"
#export NETWORK="pub_net"
#export VOLUME_SIZE="10"
#export VM_BASE_NAME="DRS_TEST"
#export TEST_USER="test_user"
#export ROLE="admin"
#END

#The scrip can create flavor by name: 4c-4r -> 4 cpu cores, 4096 Mb ram

#Script_dir, current folder
script_dir=$(dirname $0)
utils_dir=$script_dir/utils
check_openrc_script="check_openrc.sh"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

# Constants
TIMEOUT_BEFORE_NEXT_CREATION=10
UBUNTU_IMAGE_NAME="ubuntu-20.04-server-cloudimg-amd64"
CIRROS_IMAGE_NAME="cirros-0.6.2-x86_64-disk"

[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc
[[ -z $VM_QTY ]] && VM_QTY="1"
[[ -z $IMAGE ]] && IMAGE=$UBUNTU_IMAGE_NAME
[[ -z $FLAVOR ]] && FLAVOR="4c-4r"
[[ -z $NO_KEY ]] && NO_KEY="false"
[[ -z $KEY_NAME ]] && KEY_NAME="key_test"
[[ -z $HYPERVISOR_HOSTNAME ]] && HYPERVISOR_HOSTNAME=""
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $API_VERSION ]] && API_VERSION="2.74"
[[ -z $NETWORK ]] && NETWORK="pub_net"
[[ -z $SECURITY_GR ]] && SECURITY_GR="test_security_group"
[[ -z $VOLUME_SIZE ]] && VOLUME_SIZE="5"
[[ -z $VM_BASE_NAME ]] && VM_BASE_NAME="TEST_VM_FROM_SCRIPT"
[[ -z $TEST_USER ]] && TEST_USER="admin"
[[ -z $ROLE ]] && ROLE="admin"
[[ -z $ADD_KEY ]] && ADD_KEY=""
[[ -z $BATCH ]] && BATCH="false"
[[ -z $DONT_CHECK ]] && DONT_CHECK="false"
[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $WAIT_FOR_CREATED ]] && WAIT_FOR_CREATED="true"
#======================

while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
    -orc          -openrc_path  <openrc_path>
    -q,           -qty          <number_of_VMs>
    -i,           -image        <image_name>
                                The script can try to download and upload cirros and ubuntu images.
                                For this you need to define -i cirros\ubuntu
    -f,           -flavor       <flavor_name>
    -k,           -key          <key_name>
    -nk           -no_key       disable key pair (without parameter)
    -hv,          -hypervisor   <hypervisor_name>
    -net,         -network      <network_name>
    -v,           -volume_size  <volume_size_in_GB>
    -n,           -name         <vm_base_name>
    -p,           -project      <project_id>
    -t                          <time_out_between_VM_create>
    -dont_check_osc             disable check openstack cli (without parameter)
    -dont_check                 disable resource availability checks (without value)
    -da,          -dont_ask     all actions will be performed automatically (without value)
    -add                        <add command key>
                                Examples:
                                  -add \"--availability-zone \$az_name\"
                                  -add \"--hint group=\$anti_aff_gr\"
    -b            -batch        creating VMs without a timeout (without value)
    -debug                      enabled debug output (without parameter)
    -wait                       wait for vms created <true\false>
    "
      exit 0
      break ;;
          -t|-timeout) TIMEOUT_BEFORE_NEXT_CREATION="$2"
            echo "Found the -timeout <time_out_between_VM_create> option, with parameter value $TIMEOUT_BEFORE_NEXT_CREATION"
      shift ;;
    -q|-qty) qty="$2"
      echo "Found the -qty <number_of_VMs> option, with parameter value $qty"
      VM_QTY=$qty
      shift ;;
    -i|-image) image="$2"
      echo "Found the -image <image_name> option, with parameter value $image"
      IMAGE=$image
      shift ;;
    -f|-flavor) flavor="$2"
      echo "Found the -flavor <falvor_name> option, with parameter value $flavor"
      FLAVOR=$flavor
      shift;;
    -k|-key) key_name="$2"
      echo "Found the -key_name <key_name> option, with parameter value $key_name"
      KEY_NAME=$key_name
      shift;;
    -nk|no_key) NO_KEY="true"
      echo "Found the -no_name option, with parameter value $NO_KEY"
      ;;
    -hv|-hypervisor) hyper_name="$2"
      echo "Found the -hyper_name <hypervisor_name> option, with parameter value $hyper_name"
      HYPERVISOR_HOSTNAME=$hyper_name
      shift ;;
    -p|-project) project="$2"
      echo "Found the -project <project_id> option, with parameter value $project"
      PROJECT=$project
      shift ;;
    -net|-network) network="$2"
      echo "Found the -network <network_name> option, with parameter value $network"
      NETWORK=$network
      shift ;;
    -v|volume_size) volume_size="$2"
      echo "Found the -volume_size <volume_size_in_GB> option, with parameter value $volume_size"
      VOLUME_SIZE=$volume_size
      shift ;;
    -orc|-openrc_path) openrc_path="$2"
      echo "Found the -openrc_path <openrc_path> option, with parameter value $openrc_path"
      OPENRC_PATH=$openrc_path
      shift ;;
    -n|-name) name="$2"
      echo "Found the -name <vm_base_name> option, with parameter value $name"
      VM_BASE_NAME=$name
      shift ;;
    -dont_check_osc) CHECK_OPENSTACK="false"
      echo "Found the -dont_check_osc. Openstack cli check disabled"
      ;;
    -dont_check) DONT_CHECK="true"
      echo "Found the -dont_check. Resource availability checks are disabled"
      ;;
    -da|-dont_ask) DONT_ASK=true
      echo "Found the -dont_ask. All actions will be performed automatically"
      ;;
    -b|-batch) batch=true
      echo "Found the -batch. VMs will be created without a timeout"
      BATCH=$batch
      ;;
    -add) add_key="$2"
      echo "Found the -add <add command key> option, with parameter value $add_key"
      ADD_KEY=$add_key
      shift ;;
    -wait) wait_for_created="$2"
      echo "Found the -wait <true/false> option, with parameter value $wait_for_created"
      WAIT_FOR_CREATED=$wait_for_created
      shift ;;
    -debug) TS_DEBUG="true"
            echo "Found the -debug, with parameter value $TS_DEBUG"
      ;;
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

error_output () {
#  printf "%s\n" "${yellow}command not executed on $NODES_TYPE nodes${normal}"
  if [ -n "${warning_message}" ]; then
    printf "%s\n" "${yellow}$warning_message${normal}"
    warning_message=""
  fi
  printf "%s\n" "${red}$error_message - error${normal}"
  exit 1
}

## Check openrc file
#check_and_source_openrc_file () {
#    echo "Check openrc file and source it..."
#    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
#    if [ -z "$check_openrc_file" ]; then
#        echo -E "${yellow}openrc file not found in $OPENRC_PATH${normal}"
#        echo "Try to get 'openrc' from Vault"
#        printf "%s\n" "${red}openrc file not found in $OPENRC_PATH - ERROR!${normal}"
#        exit 1
#    fi
#    source $OPENRC_PATH
#    #export OS_PROJECT_NAME=$PROJECT
#}

check_and_source_openrc_file () {
#  echo "check openrc"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
#  if bash $utils_dir/$check_openrc_script 2>&1; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    exit 1
  fi
}

# Check command
check_command () {
  echo "Check $1 command..."
  command_exist="foo"
  if ! command -v $1 &> /dev/null; then
    command_exist=""
  fi
}

# check wget
check_wget () {
  echo "Check wget..."
  check_command wget
  #mock test
  #command_exist=""
  if [ -z $command_exist ]; then
    printf "%s\n" "${yellow}'wget' not installed!${normal}"
    yes_no_question="Do you want to try to install [Yes]: "
    yes_no_answer
    if [ "$yes_no_input" = "true" ]; then
      [[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })
      case $os in
        sberlinux)
          yum install -y wget
          check_command wget
          if [ -z $command_exist ]; then
            echo "For sberlinux try these commands:"
            echo "yum install -y wget"
            printf "%s\n" "${red}wget not installed - error${normal}"
            exit 1
          else
            printf "%s\n" "${green}'wget' command is available - success${normal}"
          fi
          ;;
          ubuntu)
            echo "Coming soon..."
            ;;
          *)
            echo "There is no provision for wget to be installed on the $os operating system."
            ;;
        esac
    else
      exit 1
    fi
  else
    printf "%s\n" "${green}'wget' command is available - success${normal}"
  fi
}

output_of_initial_parameters () {
  if [ $NO_KEY = "true" ]; then
    key_name_init_param="NO keypair"
  else
    key_name_init_param="$KEY_NAME"
  fi
  echo -E "
VMs will be created with the following parameters:
    OPENRC file path:                 $OPENRC_PATH
    VM base name:                     $VM_BASE_NAME
    Number of VMs:                    $VM_QTY
    Image name:                       $IMAGE
    Flavor name:                      $FLAVOR
    Security group 1:                 $SECURITY_GR: $SECURITY_GR_ID
    Key name:                         $key_name_init_param
    Project:                          $PROJECT
    User:                             $TEST_USER
    User role:                        $ROLE
    Hypervisor name:                  $HYPERVISOR_HOSTNAME
    Network name:                     $NETWORK
    Volume size:                      $VOLUME_SIZE
    OS compute api version:           $API_VERSION
    Addition key:                     $ADD_KEY
    Creating VMs without a timeout:   $BATCH
    Debug:                            $TS_DEBUG
    Wait for creating                 $WAIT_FOR_CREATED
        "

    [[ ! $DONT_ASK = "true" ]] && { read -p "Press enter to continue: "; }
}

#Check Hypervizor
check_hv () {
  echo "Check hypervisors..."
  if [ -z $HYPERVISOR_HOSTNAME ]; then
    echo "Hypervisor is not defined. VMs will be created on different hypervisors"
    host=""
  else
    host="--hypervisor-hostname $HYPERVISOR_HOSTNAME"
    echo "Check Hypervisor: $HYPERVISOR_HOSTNAME..."
    echo "Ping $HYPERVISOR_HOSTNAME..."
    if ping -c 1 $HYPERVISOR_HOSTNAME &> /dev/null; then
            printf "%s\n" "${green}There is a connection with $HYPERVISOR_HOSTNAME - success${normal}"
        else
            printf "%s\n" "${red}No connection with $HYPERVISOR_HOSTNAME - error!${normal}"
            printf "%s\n" "${red}The node $HYPERVISOR_HOSTNAME may be turned off.${normal} "
            exit 1
        fi
    echo "Check nova state on hypervizor: $HYPERVISOR_HOSTNAME..."
    nova_state_list=$(openstack compute service list)

    compute_state=$(echo "$nova_state_list" | grep -E "nova-comput(.)+$HYPERVISOR_HOSTNAME")
    echo "$compute_state" | \
      sed --unbuffered \
        -e 's/\(.*enabled\s\+|\s\+up.*\)/\o033[92m\1\o033[39m/' \
        -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
    hv_fail_state=$(echo "$compute_state" | grep -E "($HYPERVISOR_HOSTNAME(.)+(disabled|down))|(Internal Server Error \(HTTP 500\))")

    if [ -n "$hv_fail_state" ]; then
      printf "%s\n" "${red}Nova state fail on $HYPERVISOR_HOSTNAME${normal}"
      exit 1
    else
      printf "%s\n" "${green}Nova state on $HYPERVISOR_HOSTNAME - OK!${normal}"
    fi
  fi
}

# Check project
check_project () {
  echo "Check for exist project: \"$PROJECT\""
  PROJ_ID=$(openstack project list| grep -E -m 1 "\s$PROJECT\s"| awk '{print $2}')
#    PROJ_ID=$(openstack project list| grep $PROJECT| awk '{print $2}')
  if [ -z "$PROJ_ID" ]; then
    printf "%s\n" "${orange}Project \"$PROJECT\" does not exist${normal}"
    [[ ! $DONT_ASK = "true" ]] && {
      echo "Сreate a Project with name: \"$PROJECT\"?";
      read -p "Press enter to continue: ";
      }
    echo "Сreating project: \"$PROJECT\"..."
    openstack project create $PROJECT
  else
    printf "%s\n" "${green}Project: \"$PROJECT\" exist${normal}"
  fi
  echo "Check for user: \"$TEST_USER\" exist"
  USER_EXIST=$(openstack user list| grep -E " $TEST_USER "| awk '{print $4}')
  if [ -z $USER_EXIST ]; then
    printf "%s\n" "${orange}User: \"$TEST_USER\" does not exist${normal}"
    [[ ! $DONT_ASK = "true" ]] && {
      echo "Сreate a user with name: \"$TEST_USER\"?";
      read -p "Press enter to continue: ";
      }
    openstack user create --password $OS_PASSWORD $TEST_USER
  else
    printf "%s\n" "${green}User: \"$TEST_USER\" exist${normal}"
  fi
  echo "Check for role: \"$ROLE\" in project: \"$PROJECT\""
  ROLE_IN_PROJECT=$(openstack role assignment list --user $TEST_USER --project $PROJECT --names|grep -E "$ROLE(.)+$TEST_USER(.)+$PROJECT")
  if [[ -z $ROLE_IN_PROJECT ]]; then
    printf "%s\n" "${orange}Role: \"$ROLE\" does not exist in project: \"$PROJECT\"${normal}"
    [[ ! $DONT_ASK = "true" ]] && {
      echo "Сreate role: \"$ROLE\" in project: \"$PROJECT\"?";
      read -p "Press enter to continue: ";
      }
    echo "Сreating role: \"$ROLE\" in project..."
    openstack role add --project $PROJECT --user $TEST_USER $ROLE
    #Add admin user to project to view it in horizon by admin user authorization
    openstack role add --project $PROJECT --user admin admin
  else
      printf "%s\n" "${green}Role: \"$ROLE\" exist in project: \"$PROJECT\"${normal}"
  fi
  export OS_PROJECT_NAME=$PROJECT
  export OS_USERNAME=$TEST_USER
}

# Check secur_group
check_and_add_secur_group () {
    echo "Check for exist security group: \"$SECURITY_GR\""
    if [ -z "$PROJ_ID" ]; then
      check_project
    fi
#    PROJ_ID=$(openstack project list| grep -E -m 1 "\s$PROJECT\s"| awk '{print $2}')
    [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  PROJ_ID: $PROJ_ID
  "
    SECURITY_GR_ID=$(openstack security group list|grep -E "($SECURITY_GR(.)*$PROJ_ID)" | head -1 | awk '{print $2}')
    if [ -z "$SECURITY_GR_ID" ]; then
        printf "%s\n" "${orange}Security group \"$SECURITY_GR\" not found in project \"$PROJECT\"${normal}"
        [[ ! $DONT_ASK = "true" ]] && {
          echo "Сreate a Security group with a name: \"$SECURITY_GR\"?";
          read -p "Press enter to continue: ";
          }

        echo "Creating security group \"$SECURITY_GR\" in project \"$PROJECT\"..."
        SECURITY_GR_ID=$(openstack security group create --project $PROJECT $SECURITY_GR|grep "id"| head -1 | awk '{print $4}')
        echo "Security group \"$SECURITY_GR\": $SECURITY_GR_ID was created in project \"$PROJECT\""
        echo "Creating rules for \"$SECURITY_GR\" security group...";
        openstack security group rule create --egress --ethertype IPv4 --protocol tcp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol tcp $SECURITY_GR_ID
        openstack security group rule create --egress --ethertype IPv4 --protocol udp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol udp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol icmp $SECURITY_GR_ID
     else
        printf "%s\n" "${green}Security group \"$SECURITY_GR\": $SECURITY_GR_ID already exist in project \"$PROJECT\"${normal}"
     fi
}

# Check keypair
check_and_add_keypair () {
  if [ ! $NO_KEY = "false" ]; then
    key_string=""
  else
    echo "Check for exist keypair: \"$KEY_NAME\""
    KEY_NAME_EXIST=$(openstack keypair list | grep -E "\s$KEY_NAME\s"| awk '{print $2}')
    if [ -z "$KEY_NAME_EXIST" ]; then
      printf "%s\n" "${orange}Keypair \"$KEY_NAME\" not found in project \"$PROJECT\"${normal}"
      [[ ! $DONT_ASK = "true" ]] && {
        echo "Сreate a key pair with a name: \"$KEY_NAME\"?";
        read -p "Press enter to continue: ";
        }

      echo "Creating \"$KEY_NAME\" in project \"$PROJECT\"..."
      touch $script_dir/$KEY_NAME.pem
      openstack keypair create $KEY_NAME --public-key $script_dir/"$KEY_NAME".pub #> ./$KEY_NAME.pem
      chmod 400 $script_dir/$KEY_NAME.pem
      echo "Keypair \"$KEY_NAME\" was created in project \"$PROJECT\""
    else
      printf "%s\n" "${green}Keypair \"$KEY_NAME\" already exist in project \"$PROJECT\"${normal}"
    fi
    key_string="--key-name $KEY_NAME"
  fi
}

# Check network
check_network () {
  echo "Check for exist network: \"$NETWORK\""
  NETWORK_NAME_EXIST=$(openstack network list| grep "$NETWORK"| awk '{print $2}')
  if [ -z "$NETWORK_NAME_EXIST" ]; then
    printf "%s\n" "${yellow}Network \"$NETWORK\" not found in project \"$PROJECT\"${normal}"
    if [ "$NETWORK" = "pub_net" ]; then
      yes_no_question="Do you want to try to create $NETWORK [Yes]:"
      yes_no_answer
      if [ "$yes_no_input" = "true" ]; then
        CIDR=$(ip r|grep "dev external proto kernel scope"| awk '{print $1}');
        last_digit=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\.[0-9]+\.[0-9]+\.)|(\/[0-9]+)//g');
        left_side=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\/[0-9]+)//g');
        GATEWAY=$left_side$(expr $last_digit + 1);
        echo "CIDR: $CIDR, GATEWAY: $GATEWAY"
        if [ -n "$CIDR" ] && [ -n "$GATEWAY" ]; then
          mask_pub_net=$(echo "${CIDR##*/}")
          if [ "$mask_pub_net" = "27" ]; then
            case "$last_digit" in
              0)
                start_pub_net_ip="${left_side}10"
                end_pub_net_ip="${left_side}30"
                ;;
              32)
                start_pub_net_ip="${left_side}40"
                end_pub_net_ip="${left_side}62"
                ;;
              64)
                start_pub_net_ip="${left_side}70"
                end_pub_net_ip="${left_side}94"
                ;;
              96)
                start_pub_net_ip="${left_side}100"
                end_pub_net_ip="${left_side}126"
                ;;
              128)
                start_pub_net_ip="${left_side}140"
                end_pub_net_ip="${left_side}158"
                ;;
              160)
                start_pub_net_ip="${left_side}170"
                end_pub_net_ip="${left_side}190"
                ;;
              192)
                start_pub_net_ip="${left_side}200"
                end_pub_net_ip="${left_side}222"
                ;;
              224)
                start_pub_net_ip="${left_side}230"
                end_pub_net_ip="${left_side}254"
                ;;
            esac
            openstack network create \
              --external \
              --share \
              --provider-network-type flat \
              --provider-physical-network physnet1 \
              $NETWORK
            openstack subnet create \
              --subnet-range $CIDR \
              --network pub_net \
              --dhcp \
              --gateway $GATEWAY \
              --allocation-pool start=$start_pub_net_ip,end=$end_pub_net_ip \
              $NETWORK
          else
            warning_message="Script can't create network for $mask_pub_net mask"
            error_message="Network $NETWORK does not exist"
            error_output
          fi
        else
          warning_message="Script can't define CIDR or GATEWAY on this node. Try use the script on lcm or jump node"
          error_message="Network $NETWORK does not exist"
          error_output
        fi
      else
        error_message="Network $NETWORK does not exist"
        error_output
      fi
    else
      warning_message="The script can only create a 'pub_net' network"
      error_message="Network $NETWORK does not exist"
      error_output
    fi
  else
    printf "%s\n" "${green}Network \"$NETWORK\" already exist in project \"$PROJECT\"${normal}"
  fi
}

# Create image
create_image () {
  [[ ! $DONT_ASK = "true" ]] && { echo "Try to download image: \"$1\" and add to openstack?";
    read -p "Press enter to continue: "; }
  check_wget
  echo "Creating image \"$1\" in project \"$PROJECT\"..."
  [ -f $script_dir/"$1".img ] && echo "File $script_dir/$1.img exist." \
  || { echo "File $script_dir/$1.img does not exist. Try to download it..."; \
  wget https://repo.itkey.com/repository/images/"$1".img -O $script_dir/"$1".img; }
  image_exists_in_openstack
  if [ "$1" = "$CIRROS_IMAGE_NAME" ]; then
    min_disk=1
  else
    min_disk=5
  fi
  openstack image create "$1" \
    --disk-format qcow2 \
    --min-disk $min_disk \
    --container-format bare \
    --public \
    --file $script_dir/"$1".img

  IMAGE=$1
}

image_exists_in_openstack () {
  openstack image list| grep -m 1 "$1"| awk '{print $2}'
}

# Check image
check_image () {
  echo "Check for exist image: \"$IMAGE\""
  IMAGE_NAME_EXIST=$(image_exists_in_openstack $IMAGE)
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  IMAGE: $IMAGE
  IMAGE_NAME_EXIST: $IMAGE_NAME_EXIST
  "

  is_cirros_or_ubuntu=$(echo $IMAGE|grep -E "ubuntu|$UBUNTU_IMAGE_NAME|cirros|$CIRROS_IMAGE_NAME")
  is_cirros=$(echo $IMAGE|grep -E "cirros|$CIRROS_IMAGE_NAME")
  is_ubuntu=$(echo $IMAGE|grep -E "ubuntu|$UBUNTU_IMAGE_NAME")

  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  is_cirros_or_ubuntu: $is_cirros_or_ubuntu
  is_cirros: $is_cirros
  is_ubuntu: $is_ubuntu
  "
  if [ -z "$IMAGE_NAME_EXIST" ] && [ -z "$is_cirros_or_ubuntu" ]; then
    printf "%s\n" "${red}Image \"$IMAGE\" not found in project \"$PROJECT\"${normal}"
    exit 1
  elif [ -z "$IMAGE_NAME_EXIST" ] && [ -n "$is_ubuntu" ]; then
    printf "%s\n" "${orange}Image \"$IMAGE\" not found in project \"$PROJECT\"${normal}"
    if [ -z "$(image_exists_in_openstack $UBUNTU_IMAGE_NAME)" ]; then
      create_image $UBUNTU_IMAGE_NAME
    else
      echo "But image: $UBUNTU_IMAGE_NAME exists in project: $PROJECT"
      [[ ! $DONT_ASK = "true" ]] && read -p "Press enter to use this image and continue: "
      IMAGE=$UBUNTU_IMAGE_NAME
    fi
  elif [ -z "$IMAGE_NAME_EXIST" ] && [ -n "$is_cirros" ]; then
    printf "%s\n" "${orange}Image \"$IMAGE\" not found in project \"$PROJECT\"${normal}"
    if [ -z "$(image_exists_in_openstack $CIRROS_IMAGE_NAME)" ]; then
#      create_image $CIRROS_IMAGE_NAME
      create_image $IMAGE
    else
      echo "But image: $CIRROS_IMAGE_NAME exists in project: $PROJECT"
      [[ ! $DONT_ASK = "true" ]] && read -p "Press enter to use this image and continue: "
      IMAGE=$CIRROS_IMAGE_NAME
    fi
  else
    printf "%s\n" "${green}Image \"$IMAGE\" already exist in project \"$PROJECT\"${normal}"
    IMAGE=$IMAGE_NAME_EXIST
  fi
#  exit 1
}

# Check flavor
check_and_add_flavor () {
  echo "Check for exist flavor: \"$FLAVOR\""
  FLAVOR_EXST=$(openstack flavor list| grep $FLAVOR| head -n 1| awk '{print $4}')
  if [ -z $FLAVOR_EXST ]; then
    printf "%s\n" "${orange}Flavor \"$FLAVOR\" not found in project \"$PROJECT\"${normal}"
    #echo "Сreate a flavor by name (example name: \"4c-4r\" -> 4 cpu cores, 4096 Mb ram) with name: \"$FALVOR\"?"
        #read -p "Press enter to continue"
        # example FLAVOR=4c-4r
    CPU_DRAFT=$(echo "${FLAVOR%-*}")
    RAM_DRAFT=$(echo "${FLAVOR##*-}")
    CPU_QTY=$(echo "${CPU_DRAFT%c*}")
    RAM_GB=$(echo "${RAM_DRAFT%r*}")
    #echo "CPU_DRAT: $CPU_DRAFT"
        #echo "RAM_DRAFT: $RAM_DRAFT"
        #echo "CPU_QTY: $CPU_QTY"
        #echo "RAM_GB: $RAM_GB"
    #echo RAM_GB: $RAM_GB
    if [[ -z $CPU_QTY || -z $RAM_GB ]]; then
      printf "%s\n" "${orange}The falvor name format for creation should look like: <CPUs>c-<RAM GB>r instead: \"$FALVOR\"${normal}"
      printf "%s\n" "${red}Can't create a favorite by name: \"$FALVOR\"\n"
      exit 1
    fi

    let "RAM_MB = ${RAM_GB} * 1024"
    #echo $RAM_MB

    [[ ! $DONT_ASK = "true" ]] && {
      echo "Сreate a flavor with a template name <cpu qty>c_<ram GB>m with cpus: $CPU_QTY and ram: $RAM_MB Mb: \"$FLAVOR\"?";
      read -p "Press enter to continue: ";
      }

    echo "Creating flavor \"$FLAVOR\" in project \"$PROJECT\" with $CPU_QTY cpus and $RAM_MB Mb...";
    openstack flavor create --private --project $PROJECT --vcpus $CPU_QTY --ram $RAM_MB --disk 0 ${FLAVOR}_${PROJECT}
  else
    printf "%s\n" "${green}Flavor \"$FLAVOR\" already exist in project: \"$PROJECT\"${normal}"
    #openstack security group show $SECURITY_GR_ID
  fi
}

# Check vms list...
check_vms_list () {
  echo "Check vms list..."
  if [ -n "$HYPERVISOR_HOSTNAME" ]; then
    check_host="--host $HYPERVISOR_HOSTNAME"
    echo "Check vms list on $HYPERVISOR_HOSTNAME:"
    #openstack server list --all-projects --host $HYPERVISOR_HOSTNAME --long
    openstack server list --all-projects $check_host --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks
    echo "Command for check vms list on $HYPERVISOR_HOSTNAME:"
    #echo "export OS_PROJECT_NAME=$PROJECT"
    #echo "export OS_USERNAME=$TEST_USER"
    printf "%s\n" "${orange}openstack server list --all-projects $check_host --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks${normal}"
  else
    openstack server list --all-projects --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks
    echo "Command for check vms list:"
    printf "%s\n" "${orange}openstack server list --all-projects --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks${normal}"
  fi
}

# Wait vms created...
wait_vms_created () {
  building_vms=$VM_QTY
  while [ $building_vms -ne 0 ]; do
#    building_vms=$VM_QTY
    active=0
    echo "Wait for $building_vms vms created..."
    building_vms=$VM_QTY
    id_vms_list=$(openstack server list --all-projects $check_host --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks|grep -E "$1"|awk '{print $2}')
      [ "$TS_DEBUG" = true ] && echo -e "
      [DEBUG]
      building_id_vms_list: $id_vms_list
    "
    if [ -z "${id_vms_list}" ]; then
      break
    else
      for id in $id_vms_list; do
        [ "$TS_DEBUG" = true ] && echo -e "
        [DEBUG]
        id: $id
        "
        status=""
        name=""

        status=$(openstack server show $id|grep -E "\|\s+status\s+\|\s+\w+"| awk '{print $4}')
        name=$(openstack server show $id|grep -E "\|\s+name\s+\|\s+\w+"| awk '{print $4}')

        echo "server_name: $name"
        echo "status: $status"| \
          sed --unbuffered \
          -e 's/\(.*BUILD.*\)/\o033[33m\1\o033[39m/' \
          -e 's/\(.*ACTIVE.*\)/\o033[32m\1\o033[39m/' \
          -e 's/\(.*ERROR.*\)/\o033[31m\1\o033[39m/'

        if [ "$status" = ACTIVE ]; then
          active=$(( active + 1 ))
        fi
      done
      if [ "$active" -ge "$VM_QTY" ]; then
        break
      fi
      building_vms=$(( building_vms - active ))
    fi
  done
}

# VM create with timeout
# Проработать вопрос ожидания ВМ по их ID и что будет в случае батч создания (откуда брать ID)
create_vms () {

  if [ "$BATCH" = "true" ]; then
    echo "Creating $VM_QTY VMs (batch)..."
    MAX_KEY="--max $VM_QTY"
    SEQ=1
#    VM_QTY=1
  else
    echo "Creating $VM_QTY VMs with timeout: $TIMEOUT_BEFORE_NEXT_CREATION..."
    SEQ=$VM_QTY
  fi

  #export OS_PROJECT_NAME=$PROJECT
  FLAVOR=$(openstack flavor list| grep $FLAVOR| head -n 1| awk '{print $4}')
  for i in $(seq $SEQ); do
#    INSTANCE_NAME="${VM_BASE_NAME}_$i"
    if [ "$SEQ" = 1 ]; then
      INSTANCE_NAME="${VM_BASE_NAME}"
    else
      INSTANCE_NAME=$(printf "$VM_BASE_NAME-%02d" $i)
    fi
    echo "Check for VM: \"$INSTANCE_NAME\" exist"
    VM_EXIST=$(openstack server list| grep $INSTANCE_NAME| awk '{print $4}')
    if [ -n "$VM_EXIST" ]; then
      printf "%s\n" "${orange}VM: \"$INSTANCE_NAME\" is already exist in project \"$PROJECT\"${normal}"
      if [[ ! $DONT_ASK = "true" ]]; then
#        echo "Сreate VM: \"$INSTANCE_NAME\" in project \"$PROJECT\"?"
#        read -p "Press enter to continue: "
#        while true; do
        read -p "Сreate VM: \"$INSTANCE_NAME\" in project \"$PROJECT\" [Yes]: " yn
          yn=${yn:-"Yes"}
        if [ "$yn" != Yes ]; then
          continue
        fi
      fi
    fi
    echo "Creating VM: $INSTANCE_NAME"

  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  VM_BASE_NAME: $VM_BASE_NAME
  IMAGE: $IMAGE
  FLAVOR: $FLAVOR
  SECURITY_GR_ID: $SECURITY_GR_ID
  key_string: $key_string
  host: $host
  API_VERSION: $API_VERSION
  NETWORK: $NETWORK
  VOLUME_SIZE: $VOLUME_SIZE
  VM_QTY: $VM_QTY
  ADD_KEY: $ADD_KEY
  MAX_KEY: $MAX_KEY

  Openstack server create command:
  openstack server create \
    $INSTANCE_NAME \
    --image $IMAGE \
    --flavor $FLAVOR \
    --security-group $SECURITY_GR_ID \
    $key_string \
    $host \
    --os-compute-api-version $API_VERSION \
    --network $NETWORK \
    --boot-from-volume $VOLUME_SIZE \
    $ADD_KEY $MAX_KEY
"
#  KEY_NAME: $KEY_NAME

    openstack server create \
      $INSTANCE_NAME \
      --image $IMAGE \
      --flavor $FLAVOR \
      --security-group $SECURITY_GR_ID \
      $key_string \
      $host \
      --os-compute-api-version $API_VERSION \
      --network $NETWORK \
      --boot-from-volume $VOLUME_SIZE \
      $ADD_KEY $MAX_KEY

    [[ $i -ne $VM_QTY ]] && { sleep $TIMEOUT_BEFORE_NEXT_CREATION; }
  done

  if [ "$WAIT_FOR_CREATED" = true ]; then
    wait_vms_created $VM_BASE_NAME
    check_vms_list
  else
    check_vms_list
  fi
}

output_of_initial_parameters

#check_openstack_cli
if [[ $CHECK_OPENSTACK = "true" ]]; then
  if ! bash $utils_dir/check_openstack_cli.sh; then
    echo -e "\033[31mFailed to check openstack cli - error\033[0m"
    exit 1
  fi
fi

check_and_source_openrc_file


[[ ! $DONT_CHECK = "true" ]] && \
  {
  check_hv
  check_project
  check_network
  check_and_add_secur_group
  check_image
  check_and_add_flavor
  check_and_add_keypair
  }
#if [ "$BATCH" = "true" ]; then
#  create_vms_batch
#else
  create_vms
#fi
export OS_PROJECT_NAME='admin'

