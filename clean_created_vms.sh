#!/bin/bash

# The script deletes VMs and Volumes for the project. The project can be specified as a parameter. By default the project is "admin" 
# exemple start command: bash clean_openstack.sh ha_test_project_2
# Add start keys and help (dont_ask key)

OPENRC=$HOME/openrc
default_project="admin"
tmp_output="region_resource_list_before_clean"
envs_file_name=".envs_create_vms"
script_dir=$(dirname $0)

#[[ ! -z $1 ]] && PROJECT=$1
[[ -z $DONT_ASK ]] && DONT_ASK="false"

define_parameters () {
  [ "$TS_DEBUG" = true ] && echo "[TS_DEBUG]: \"\$1\": $1"
  [ "$count" = 1 ] && [[ -n $1 ]] && { PROJECT=$1; echo "Command parameter found with value $PROJECT"; }
#  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      The script cleanup VMs and Volumes from openstack project (default: 'admin')
      -dont_ask, -da                    cleanup with no question
      -project, p    <project_name\id>  project name
"
      exit 0
      break ;;
	  -dont_ask|-da) DONT_ASK="ture"
	   echo "Found the -dont_ask option, with parameter value $DONT_ASK"
      ;;
    -p|-project) PROJECT="$2"
	    echo "Found the -project <project_name> option, with parameter value $PROJECT"
      shift ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
  esac
  shift
done

echo "Check VMs and volumes for project $PROJECT"

# Check openrc file
check_and_source_openrc_file () {
    echo "Check openrc file and source it..."
    check_openrc_file=$(ls -f $OPENRC 2>/dev/null)
    if [ -z "$check_openrc_file" ]; then
        printf "%s\n" "${red}openrc file not found in $OPENRC - ERROR!${normal}"
        exit 1
    fi
    source $OPENRC
    #export OS_PROJECT_NAME=$PROJECT
}

# Check envs file
check_and_source_envs_file () {
    echo "Check envs file and source it..."
    check_envs_file=$(ls -f $script_dir/$envs_file_name 2>/dev/null)
    if [ -n "$check_envs_file" ]; then
        source $script_dir/$envs_file_name
    fi
#    source $OPENRC
    #export OS_PROJECT_NAME=$PROJECT
}

delete_vm () {
#    echo "Deleting $(openstack server list --project $PROJECT |grep $1 |awk '{print $4}')..."
    openstack server delete $1
}

delete_volume () {

#    attached_to=$(openstack volume list --project $PROJECT |grep $1 |awk '{print $11}')
#    if [ -z $attached_to ]; then
#        attached_to="None"
#    fi
#    echo "Deleting volume $1 Attached to \"$attached_to\"..."
#    openstack volume delete $1
  openstack volume set --state error $1
  openstack volume delete $1

}

clean_vms () {
  echo "Check VMs..."
  [[ -z $PROJECT ]] && PROJECT=$default_project
  openstack server list --project $PROJECT -c Name -c id -c status -c power_state -c availability_zone -c host > /tmp/$tmp_output
#  echo $openstack_server_list > /tmp/$tmp_output
  ls -f /tmp/$tmp_output
  if [ ! $? -eq 0 ]; then
    echo "File /tmp/$tmp_output not found"
    exit 1
  fi
  if [ -z $VM_BASE_NAME ]; then
    VMs_ID=$(cat /tmp/$tmp_output |grep -E 'ACTIVE|ERROR|SHUTOFF|BUILD'| awk '{print $2}')
  else
    VMs_ID=$(cat /tmp/$tmp_output |grep -E $VM_BASE_NAME| awk '{print $2}')
  fi
  if [ -z "$VMs_ID" ]; then
    echo "Failed to compile a list of VM IDs for subsequent deletion."
    exit 1
  else
    if [ "$DONT_ASK" = false ]; then
      echo -E "
Delete the following VMs?:
"
      awk -v ids="$VMs_ID" '
        BEGIN {
          split(ids, vm_ids, " ")
          for (i in vm_ids) {
              vm_ids_lookup[vm_ids[i]] = 1
          }
        }
        NR > 3 && !/^\+/ && $2 in vm_ids_lookup { print $2 " | " $4 }
        ' /tmp/$tmp_output

      read -p "Press enter to continue: "
    fi
    # Define Volume id for deleted VMs
    Volumes_ID=""
    for id in $VMs_ID; do
      Volumes_ID="$Volumes_ID $(openstack server show  $id -c volumes_attached -f value | grep -oP "'id': '\K[a-f0-9-]+")"
    done
    for id in $VMs_ID; do
      delete_vm $id
    done
    echo "delete commands sent..."
    openstack server list --project $PROJECT
  fi
}

clean_volumes () {
  echo "Delete Volumes..."
#  openstack volume list --project $PROJECT|grep -E 'available|in-use' | tee /tmp/$tmp_output
#  ls -f /tmp/$tmp_output
#  if [ ! $? -eq 0 ]; then
#    echo "File /tmp/$tmp_output not found"
#    exit 1
#  fi
#  volumes_ID=$(cat /tmp/$tmp_output|awk '{print $2}')
#  volumes_names=$(openstack volume list --project $PROJECT|grep -E 'available|in-use' |awk '{print $2}')
  # echo $volumes_ID
  if [[ -n $Volumes_ID ]]; then
#    echo "Volumes list:"
#    for name in $volumes_names; do
#      [ -z $name ] && name="None"
#      echo "$name"
#    done

    if [ "$DONT_ASK" = false ]; then

      echo -E "
Delete the following disks associated with removed VMs?:
$Volumes_ID
"
      read -p "Press enter to continue: "
    fi
    for id in $Volumes_ID; do
      delete_volume $id
    done
    echo "delete commands sent..."
    openstack volume list
  else
    echo "Volumes not found"
  fi
}

check_and_source_openrc_file
check_and_source_envs_file
clean_vms
clean_volumes

