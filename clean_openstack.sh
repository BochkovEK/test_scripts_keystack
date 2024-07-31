#!/bin/bash

# The script deletes VMs and Volumes for the project. The project can be specified as a parameter. By default the project is "admin" 
# exemple start command: bash clean_openstack.sh ha_test_project_2
# Add start keys and help (dont_ask key)

OPENRC=$HOME/openrc
PROJECT="admin"

[[ ! -z $1 ]] && PROJECT=$1
#[[ -z $DONT_ASK ]] && DONT_ASK="false"

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
    echo "Deleting $(openstack server list --project $PROJECT |grep $1 |awk '{print $4}')..."
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
    #!!!!
#    openstack volume set --state error ID
#id_list=$(openstack volume list|grep fc_hdd-itkey|awk '{print $2}')
#for id in $id_list; do openstack volume set --state error $id; done
#for id in $id_list; do openstack volume delete $id; done
#
##shutoff
#id_list=$(openstack server list|grep fc_hdd|awk '{print $2}')
#for id in $id_list; do openstack server start $id; done
##error
#for id in $id_list; do openstack server set --state error $id; done
    #!!!!

#    openstack server list
    VMs_ID=$(openstack server list --project $PROJECT|grep -E 'ACTIVE|ERROR|SHUTOFF' |awk '{print $2}')
    VMs_names=$(openstack server list --project $PROJECT|grep -E 'ACTIVE|ERROR|SHUTOFF' |awk '{print $4}')
   # |grep ACTIVE |awk '{print $4}')
    if [[ ! -z $VMs_ID ]]; then
        echo "VMs list:"
        for name in $VMs_names; do
            echo "   $name"
        done
        echo -E "
Delete all VMs?
        "

        read -p "Press enter to continue: "
        openstack server delete $VMs_ID
#        for id in $VMs_ID; do
#            delete_vms $id
#        done
        echo "Remove all VMs completed"
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
            #echo "   Attached to $name"
	    echo "$name"
        done

        #volumes_ID_na=$(openstack volume list |grep 'available' |awk '{print $2}')
        #for name in $volumes_ID_na; do
        #    echo "   Volume $name not attached"
        #done

        echo -E "
Delete all volumes?
        "

        read -p "Press enter to continue: "
#        openstack volume delete $volumes_ID
        for id in $volumes_ID; do
          delete_volume $id
        done
        echo "Deletion command send..."
        openstack volume list
    else
	echo "Volumes not found"
    fi
}

check_and_source_openrc_file
clean_vms
clean_volumes

