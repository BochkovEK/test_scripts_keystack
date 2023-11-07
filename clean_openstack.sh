#!/bin/bash

# The script deletes VMs and Volumes for the project. The project can be specified as a parameter. By default the project is "admin" 
# exzmple start command: bash clean_openstack.sh ha_test_project_2 

OPENRC=./openrc
PROJECT="admin"

[[ ! -z $1 ]] && PROJECT=$1

echo "Check VMs and volumes for project $PROJECT"

delete_vms () {
    echo "Deleting $(openstack server list --project $PROJECT |grep $1 |awk '{print $4}')..."
    openstack server delete $1
}

delete_volumes () {
    attached_to=$(openstack volume list --project $PROJECT |grep $1 |awk '{print $11}')
    if [ -z $attached_to ]; then
        attached_to="None"
    fi
    echo "Deleting volume $1 Attached to \"$attached_to\"..."
    openstack volume delete $1
}

clean_vms () {
    echo "Check VMs..."
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

        read -p "Press enter to continue"
        for id in $VMs_ID; do
            delete_vms $id
        done
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
            echo "   Attached to $name"
        done

        volumes_ID_na=$(openstack volume list |grep 'available' |awk '{print $2}')
        for name in $volumes_ID_na; do
            echo "   Volume $name not attached"
        done

        echo -E "
Delete all volumes?
        "

        read -p "Press enter to continue"
        for id in $volumes_ID; do
            delete_volumes $id
        done
        echo "Remove all volumes completed"
        openstack volume list
    else
	echo "Volumes not found"
    fi
}

source $OPENRC
#echo
clean_vms
clean_volumes


