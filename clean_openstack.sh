#!/bin/bash

# The script deletes VMs and Volumes for the project. The project can be specified as a parameter. By default the project is "admin" 
# exemple start command: bash clean_openstack.sh ha_test_project_2
# Add start keys and help (dont_ask key)

OPENRC=$HOME/openrc
PROJECT="admin"

[[ ! -z $1 ]] && PROJECT=$1
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
      -dont_ask                         cleanup with no question
      -project, p    <project_name\id>  project name
"
      exit 0
      break ;;
	  -dont_ask) DONT_ASK="$2"
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

#    openstack server list
  VMs_ID=$(openstack server list --project $PROJECT|grep -E 'ACTIVE|ERROR|SHUTOFF|BUILD' |awk '{print $2}')
  VMs_names=$(openstack server list --project $PROJECT|grep -E 'ACTIVE|ERROR|SHUTOFF|BUILD' |awk '{print $4}')
 # |grep ACTIVE |awk '{print $4}')
  if [[ ! -z $VMs_ID ]]; then
    echo "VMs list:"
    for name in $VMs_names; do
        echo "   $name"
    done
    if [ "$DONT_ASK" = false ]; then
      echo -E "
  Delete all VMs?
"
      read -p "Press enter to continue: "
    fi
      for id in $VMs_ID; do
        delete_vm $id
      done
      echo "delete commands sent..."
      openstack server list --project $PROJECT
  else
    echo "VMs not found"
  fi
}

clean_volumes () {
  echo "Check Volumes..."
  volumes_ID=$(openstack volume list --project $PROJECT|grep -E 'available|in-use' |awk '{print $2}')
  volumes_names=$(openstack volume list --project $PROJECT|grep -E 'available|in-use' |awk '{print $2}')
  # echo $volumes_ID
  if [[ ! -z $volumes_ID ]]; then
    echo "Volumes list:"
    for name in $volumes_names; do
      [ -z $name ] && name="None"
      echo "$name"
    done


    if [ "$DONT_ASK" = false ]; then
      echo -E "
Delete all volumes?
"
      read -p "Press enter to continue: "
    fi
    for id in $volumes_ID; do
      delete_volume $id
    done
    echo "delete commands sent..."
    openstack volume list
  else
    echo "Volumes not found"
  fi
}

check_and_source_openrc_file
clean_vms
clean_volumes

