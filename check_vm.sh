#!/bin/bashq!

# !!! Сделать претест по пингу
# The script checks access to the VM on HV

key_name=key_test.pem
hypervisor_name=cmpt-1
command_str="ls -la"
user=ubuntu

OPENRC_PATH="$HOME/openrc"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

# Functions

batch_run_command() {
    rm ~/.ssh/known_hosts
    VMs_IPs=$(openstack server list --host $hypervisor_name |grep ACTIVE |awk '{print $8}')
    echo -E "
    Start check VMs with parameters:
        Hypervisor:   $hypervisor_name
        Key:          $key_name
        User name:    $user
        Command:      $command_str
        "

    read -p "Press enter to continue"

    for raw_string_ip in $VMs_IPs; do
        IP="${raw_string_ip##*=}"
        sleep 1
        if ping -c 2 $IP &> /dev/null; then
            printf "%40s\n" "${green}There is a connection with $IP - success${normal}"
            ssh -t -o StrictHostKeyChecking=no -i $key_name $user@$IP "$command_str"
        else
            printf "%40s\n" "${red}No connection with $IP - error!${normal}"
        fi
    done
}

# Check openrc file
check_openrc_file () {
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && (echo "openrc file not found in $OPENRC_PATH"; exit 1)

    source $OPENRC_PATH
}

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -hv         <hypervisor_name>
        -u, -user   <user_name_on_VM_OS>
        -c, command <command_on_VM>
        -k, -key    <key_pair_private_part_file>
        "
            exit 0
            break ;;
        -hv) hypervisor_name="$2"
            echo "Found the -hv option, with parameter value $hypervisor_name"
            shift ;;
        -u|-user) user="$2"
            echo "Found the -user option, with parameter value $user"
            shift ;;
        -c|-command) command_str="$2"
            echo "Found the -command option, with parameter value $command_str"
            shift ;;
        -k|-key) key_name="$2"
	    echo "Found the -key option, with parameter value $key_name"
            shift ;;	    
        --) shift
            break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

#rm -rf /root/.ssh/known_hosts
check_openrc_file
batch_run_command
