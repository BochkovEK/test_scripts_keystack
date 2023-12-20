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

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)

# Constants
TIMEOUT_BEFORE_NEXT_CREATION=10
UBUNTU_IMAGE_NAME="ubuntu-20.04-server-cloudimg-amd64"

[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc
[[ -z $VM_QTY ]] && VM_QTY="1"
[[ -z $IMAGE ]] && IMAGE="ubuntu-20.04-server-cloudimg-amd64"
[[ -z $FLAVOR ]] && FLAVOR="4c-4r"
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
#======================

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -q,           -qty		<number_of_VMs>
        -i,           -image		<image_name>
        -f,           -flavor		<falvor_name>
        -k,           -key		<key_name>
        -hv,          -hypervisor	<hypervisor_name>
        -net,         -network	<network_name>
        -v,           -volume_size 	volume_size_in_GB>
        -n,           -name 		<vm_base_name>
        -p,           -project	<project_id>
        -t            <time_out_between_VM_create>
        -dont_check   disable resource availability checks
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
        -n|-name) name="$2"
          echo "Found the -name <vm_base_name> option, with parameter value $name"
          VM_BASE_NAME=$name
          shift ;;
        -dont_check) dont_check=true
          echo "Found the -dont_check Resource availability checks are disabled"
          shift ;;
        --) shift
            break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

# Define parameters
count=1
for param in "$@"
do
        echo "Parameter #$count: $param"
        count=$(( $count + 1 ))
done

output_of_initial_parameters () {
      echo -E "
VMs will be created with the following parameters:
        VM base name: $VM_BASE_NAME
        Number of VMs: $VM_QTY
        Image name: $IMAGE
        Flavor name: $FLAVOR
        Security group 1: $SECURITY_GR: $SECURITY_GR_ID
        Key name: $KEY_NAME
        Project: $PROJECT
        User: $TEST_USER
        User role: $ROLE
        Hypervisor name: $HYPERVISOR_HOSTNAME
        Network name: $NETWORK
        Volume size: $VOLUME_SIZE
        OS compute api version: $API_VERSION
        "

    read -p "Press enter to continue"
}

# Check openrc file
check_and_source_openrc_file () {
    echo "Check openrc file and source it..."
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    if [ -z "$check_openrc_file" ]; then
        printf "%s\n" "${red}openrc file not found in $OPENRC_PATH - ERROR!${normal}"
        exit 1
    fi
    source $OPENRC_PATH
    #export OS_PROJECT_NAME=$PROJECT
}

#Check Hypervizor
chech_hv () {
  echo "Check hypervisors..."
  if [ -z $HYPERVISOR_HOSTNAME ]; then
    echo "Hypervisor is not defined. VMs will be created on different hypervisors"
    host=""
  else
    host="--hypervisor-hostname $HYPERVISOR_HOSTNAME"
    echo "Check Hypervizor: $HYPERVISOR_HOSTNAME..."
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
    PROJ_ID=$(openstack project list| grep $PROJECT| awk '{print $2}')
    if [ -z $PROJ_ID ]; then
        printf "%s\n" "${orange}Project \"$PROJECT\" does not exist${normal}"
        echo "Сreate a Project with name: \"$PROJECT\"?"
        read -p "Press enter to continue"
        openstack project create $PROJECT
    else
        printf "%s\n" "${green}Project: \"$PROJECT\" exist${normal}"
    fi
    echo "Check for user: \"$TEST_USER\" exist"
    USER_EXIST=$(openstack user list| grep -E " $TEST_USER "| awk '{print $4}')
    if [ -z $USER_EXIST ]; then
        printf "%s\n" "${orange}User: \"$TEST_USER\" does not exist${normal}"
        echo "Сreate a user with name: \"$TEST_USER\"?"
        read -p "Press enter to continue"
        openstack user create --password $OS_PASSWORD $TEST_USER
    else
        printf "%s\n" "${green}User: \"$TEST_USER\" exist${normal}"
    fi
    echo "Check for role: \"$ROLE\" in project: \"$PROJECT\""
    ROLE_IN_PROJECT=$(openstack role assignment list --user $TEST_USER --project $PROJECT --names|grep -E "$ROLE(.)+$TEST_USER(.)+$PROJECT")
    if [[ -z $ROLE_IN_PROJECT ]]; then
        printf "%s\n" "${orange}Role: \"$ROLE\" does not exist in project: \"$PROJECT\"${normal}"
        echo "Сreate role: \"$ROLE\" in project: \"$PROJECT\"?"
        read -p "Press enter to continue"
        openstack role add --project $PROJECT --user $TEST_USER $ROLE
        #Add admin user to project to view it in horizon by admin user authorization
        openstack role add --project $PROJECT --user admin admin
    else
        printf "%s\n" "${green}Role: \"$ROLE\" exist in project: \"$PROJECT\"${normal}"
    fi
    #export OS_PROJECT_NAME=$PROJECT
    export OS_USERNAME=$TEST_USER
}

# Check secur_group
check_and_add_secur_group () {
    echo "Check for exist security group: \"$SECURITY_GR\""
    PROJ_ID=$(openstack project list| grep $PROJECT| awk '{print $2}')
    SECURITY_GR_ID=$(openstack security group list|grep -E "($SECURITY_GR(.)*$PROJ_ID)" | head -1 | awk '{print $2}')
    if [ -z $SECURITY_GR_ID ]; then
        printf "%s\n" "${orange}Security group \"$SECURITY_GR\" not found in project \"$PROJECT\"${normal}"

        echo "Сreate a Security group with a name: \"$SECURITY_GR\"?"
        read -p "Press enter to continue"

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
  echo "Check for exist keypair: \"$KEY_NAME\""
  KEY_NAME_EXIST=$(openstack keypair list | grep $KEY_NAME| awk '{print $2}')
  if [ -z "$KEY_NAME_EXIST" ]; then
    printf "%s\n" "${orange}Keypair \"$KEY_NAME\" not found in project \"$PROJECT\"${normal}"
    echo "Сreate a key pair with a name: \"$KEY_NAME\"?"
    read -p "Press enter to continue"

    echo "Creating \"$KEY_NAME\" in project \"$PROJECT\"..."
    touch ./$KEY_NAME.pem
    openstack keypair create $KEY_NAME --public-key ./"$KEY_NAME".pub #> ./$KEY_NAME.pem
    chmod 400 ./$KEY_NAME.pem
    echo "Keypair \"$KEY_NAME\" was created in project \"$PROJECT\""
  else
    printf "%s\n" "${green}Keypair \"$KEY_NAME\" already exist in project \"$PROJECT\"${normal}"
  fi
}

# Check network
check_network () {
  echo "Check for exist network: \"$NETWORK\""
  NETWORK_NAME_EXIST=$(openstack network list| grep "$NETWORK"| awk '{print $2}')
  if [ -z "$NETWORK_NAME_EXIST" ]; then
    printf "%s\n" "${red}Image \"$NETWORK\" not found in project \"$PROJECT\"${normal}"
    exit 1
  else
    printf "%s\n" "${green}Network \"$NETWORK\" already exist in project \"$PROJECT\"${normal}"
  fi
}

# Check image
check_image () {
  echo "Check for exist image: \"$IMAGE\""
  IMAGE_NAME_EXIST=$(openstack image list| grep "$IMAGE"| awk '{print $2}')
  if [ -z "$IMAGE_NAME_EXIST" ] && [[ ! $IMAGE =~ ubuntu|ubuntu-22.04.2-live-server-amd64 ]]; then
    printf "%s\n" "${red}Image \"$IMAGE\" not found in project \"$PROJECT\"${normal}"
    exit 1
  elif [ -z "$IMAGE_NAME_EXIST" ] && [[ $IMAGE =~ ubuntu|ubuntu-22.04.2-live-server-amd64 ]]; then
    printf "%s\n" "${orange}Image \"$IMAGE\" not found in project \"$PROJECT\"${normal}"
    echo "Try to download image: \"$UBUNTU_IMAGE_NAME\" and add to openstack?"
    read -r -p "Press enter to continue"

    echo "Creating image \"$UBUNTU_IMAGE_NAME\" in project \"$PROJECT\"..."
    [ -f ./"$UBUNTU_IMAGE_NAME".img ] && echo "File ./$UBUNTU_IMAGE_NAME.img exist." \
    || { echo "File ./$UBUNTU_IMAGE_NAME.img does not exist. Try to download it..."; \
    wget https://repo.itkey.com/repository/images/"$UBUNTU_IMAGE_NAME".img; }
    openstack image create "$UBUNTU_IMAGE_NAME" \
      --disk-format qcow2 \
      --min-disk 5 \
      --container-format bare \
      --public \
      --file ./"$UBUNTU_IMAGE_NAME".img
  else
    printf "%s\n" "${green}Image \"$IMAGE\" already exist in project \"$PROJECT\"${normal}"
  fi
}

# Check flavor
check_and_add_flavor () {
    echo "Check for exist flavor: \"$FLAVOR\""
    FLAVOR_EXST=$(openstack flavor list| grep $FLAVOR| awk '{print $4}')
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
        if [[ -z $CPU_QTY || -z $RAM_GB ]]; then
            printf "%s\n" "${orange}The falvor name format for creation should look like: <CPUs>c-<RAM GB>r instead: \"$FALVOR\"${normal}"
            printf "%s\n" "${red}Can't create a favorite by name: \"$FALVOR\"\n"
            exit 1
        fi

        let "RAM_MB = ${RAM_GB} * 1024"
        #echo $RAM_MB

        echo "Сreate a flavor with a template name <cpu qty>c_<ram GB>m with cpus: $CPU_QTY and ram: $RAM_MB Mb: \"$FLAVOR\"?"
        read -p "Press enter to continue"

        echo "Creating \"$FLAVOR\" in project \"$PROJECT\" with $CPU_QTY cpus and $RAM_MB Mb...";
        openstack flavor create --public --vcpus $CPU_QTY --ram $RAM_MB --disk 0 $FLAVOR
    else
        printf "%s\n" "${green}Flavor \"$FLAVOR\" already exist in project: \"$PROJECT\"${normal}"
        #openstack security group show $SECURITY_GR_ID
    fi
}

# VM create
create_vms () {

  export OS_PROJECT_NAME=$PROJECT

  for i in $(seq $VM_QTY); do
    INSTANCE_NAME="${VM_BASE_NAME}_$i"
    echo "Check for VM: \"$INSTANCE_NAME\" exist"
    VM_EXIST=$(openstack server list| grep $INSTANCE_NAME| awk '{print $4}')
    if [ -n "$VM_EXIST" ]; then
      printf "%s\n" "${orange}VM: \"$INSTANCE_NAME\" is already exist in project \"$PROJECT\"${normal}"
      echo "Сreate VM: \"$INSTANCE_NAME\" in project \"$PROJECT\"?"
      read -p "Press enter to continue"
    fi
  echo "Creating VM: $INSTANCE_NAME"

#  echo "openstack server create " \
#    "--image '$IMAGE' " \
#    "--flavor '$FLAVOR' " \
#    "--security-group '$SECURITY_GR_ID' " \
#    "--key-name '$KEY_NAME' " \
#    "'$host' " \
#    "--os-compute-api-version '$API_VERSION' " \
#    "--network '$NETWORK' " \
#    "--boot-from-volume '$VOLUME_SIZE' " \
#    "'$INSTANCE_NAME'"

    openstack server create \
      --image $IMAGE \
      --flavor $FLAVOR \
      --security-group $SECURITY_GR_ID \
      --key-name $KEY_NAME \
      $host \
      --os-compute-api-version $API_VERSION \
      --network $NETWORK \
      --boot-from-volume $VOLUME_SIZE \
      $INSTANCE_NAME

    sleep $TIMEOUT_BEFORE_NEXT_CREATION
  done

  export OS_PROJECT_NAME='admin'

# Check vms list...
  if [ -n "$HYPERVISOR_HOSTNAME" ]; then
    check_host="--host $HYPERVISOR_HOSTNAME"
    echo "Check vms list on $HYPERVISOR_HOSTNAME:"
    #openstack server list --all-projects --host $HYPERVISOR_HOSTNAME --long
    openstack server list --all-projects $check_host --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks
    echo "Command for check vms list on $HYPERVISOR_HOSTNAME:"
    #echo "export OS_PROJECT_NAME=$PROJECT"
    #echo "export OS_USERNAME=$TEST_USER"
    printf "%s\n" "${orange}openstack server list --all-projects $check_host --long -c Project -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks${normal}"
  else
    echo "Check vms list..."
    openstack server list --all-projects --long -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks
    echo "Command for check vms list:"
    printf "%s\n" "${orange}openstack server list --all-projects --long -c Project -c Name -c Flavor -c Status -c 'Power State' -c Host -c ID -c Networks${normal}"
  fi
}

output_of_initial_parameters
check_and_source_openrc_file
chech_hv
check_project
check_and_add_secur_group
[[ ! $dont_check = "true" ]] && \
  {
  check_image;
  check_and_add_flavor;
  check_network
  check_and_add_keypair;
  }
create_vms
