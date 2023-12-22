#!/bin/bash

# The script determines the node for which the nova service is disabled and trying to turn it on
# This script can take the path to the "openrc" file as a parameter (./nova_up.sh /installer/config/openrc)

OPENRC_PATH=$HOME/openrc

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ -z $TRY_TO_RISE ]] && TRY_TO_RISE="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $REGION ]] && REGION="region-ps"

#======================

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -o,     -openrc             <path_openrc_file>
        -r,     -region             <region_name>
        -dtr,   -dont_try_to_rise   If nova is not active on some nodes, then there will be no attempt to rise it
"
            exit 0
            break ;;
	-o|-openrc) OPENRC_PATH="$2"
	  echo "Found the -openrc <path_openrc_file> option, with parameter value $OPENRC_PATH"
    shift ;;
  -r|-region) REGION="$2"
	  echo "Found the -region <region_name> option, with parameter value $REGION"
    shift ;;
  -dtr|-dont_try_to_rise) TRY_TO_RISE="false"
	  echo "Found the -dont_try_to_rise <dont_try_to_rise_compute_node>"
    ;;
  --) shift
    break ;;
  *) echo "$1 is not an option";;
    esac
    shift
done

# functions
# Check openrc file
Check_openrc_file () {
    echo "Check openrc file here: $OPENRC_PATH"
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    #echo $OPENRC_PATH
    #echo $check_openrc_file
    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
}

# Check nova srvice list
Check_nova_srvice_list () {
    echo "Check nova srvice list..."
    echo "$nova_state_list" | \
        sed --unbuffered \
            -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
            #-e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
}

# Check connection to nova nodes
Check_connection_to_nova_nodes () {
    echo "Check connection to nova nodes..."
    for host in $comp_and_ctrl_nodes;do
        host $host
        sleep 1
        if ping -c 2 $host &> /dev/null; then
            printf "%40s\n" "${green}There is a connection with $host - success${normal}"
        else
            printf "%40s\n" "${red}No connection with $host - error!${normal}"
            #unreachable_nova_node=$(host $host |grep -E "ctrl|cmpt")
            #if [ -n "$unreachable_nova_node" ]; then
            #    printf "%40s\n" "${red}One of the nova cluster nodes is unreachable!${normal}"
            echo -e "${red}The node may be turned off.${normal}\n"
            #exit 1
            #fi
        fi
    done
}

# Check disabled computes in nova
Check_disabled_computes_in_nova () {
    echo "Check disabled computes in nova..."
    cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')

    # Trying to raise and enable nova service on cmpt
    if [ -n "$cmpt_disabled_nova_list" ]; then
        if [ "$TRY_TO_RISE" = true ] ; then
          for cmpt in $cmpt_disabled_nova_list; do
            echo "Trying to raise and enable nova service on $cmpt"
            read -r -p "Press enter to continue"
            openstack compute service set --enable "${cmpt}" nova-compute
            openstack compute service set --up "${cmpt}" nova-compute
          done
          nova_state_list=$(openstack compute service list)
          echo "$nova_state_list" | \
            sed --unbuffered \
              -e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
              -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
              -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'

        cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')
        if [ -n "$cmpt_disabled_nova_list" ]; then
          for cmpt in $cmpt_disabled_nova_list; do
            printf "%40s\n" "${red}Failed to start nova service on $cmpt${normal}"
            exit 1
          done
        fi
      fi
    fi
}

# Check docker consul
Check_docker_consul () {
    echo "Check consul docker on nodes..."

    for host in $comp_and_ctrl_nodes;do
        echo "consul on $host"
        docker_consul=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $host "docker ps | grep consul")
        echo "$docker_consul" | \
            sed --unbuffered \
                -e 's/\(.*Up.*\)/\o033[92m\1\o033[39m/' \
                -e 's/\(.*Restarting.*\)/\o033[31m\1\o033[39m/' \
                -e 's/\(.*unhealthy.*\)/\o033[31m\1\o033[39m/'
    done
}

# Check members list
Check_members_list () {
    #ctrl_node=$(echo "$comp_and_ctrl_nodes" | grep -E "(nova-scheduler" | awk '{print $6}')
    echo "Check members list on ${ctrl_node_array[0]}..."
    members_list=$(ssh -t -o StrictHostKeyChecking=no "${ctrl_node_array[0]}" "docker exec -it consul consul members list")
    echo "$members_list" | \
            sed --unbuffered \
                -e 's/\(.*alive.*\)/\o033[92m\1\o033[39m/' \
                #-e 's/\(.*Restarting.*\)/\o033[31m\1\o033[39m/' \
                #-e 's/\(.*unhealthy.*\)/\o033[31m\1\o033[39m/'
}

# Check consul logs
Check_consul_logs () {
    echo "Check consul logs..."
    #ctrl_node=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)" | awk '{print $6}')
    leader_ctrl_node=$(ssh -t -o StrictHostKeyChecking=no "${ctrl_node_array[0]}" "docker exec -it consul consul operator raft list-peers" | grep leader | awk '{print $1}')
    echo "Leader consul node is $leader_ctrl_node"
    ssh -o StrictHostKeyChecking=no "$leader_ctrl_node" tail -7 /var/log/kolla/autoevacuate.log | \
        sed --unbuffered \
        -e 's/\(.*Force off.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*Server.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*Evacuating instance.*\)/\o033[33m\1\o033[39m/' \
        -e 's/\(.*Starting fence.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*IPMI "power off".*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*disabled,.*\)/\o033[33m\1\o033[39m/'; \
    ssh -o StrictHostKeyChecking=no -t "$leader_ctrl_node" 'violet=$(tput setaf 5); normal=$(tput sgr0); DATE=$(date); printf "%s\n" "${violet}${DATE}${normal}"'
}

# Check consul config
Check_consul_config () {
  echo "Check consul config..."
  ipmi_fencing_state=$(ssh -o StrictHostKeyChecking=no "$leader_ctrl_node" cat /etc/kolla/consul/region-config_"${REGION}".json| \
  grep -E '"bmc": \w|"ipmi": \w|alive_compute_threshold|dead_compute_threshold|')
  echo "$ipmi_fencing_state" | \
            sed --unbuffered \
                -e 's/\(.*true.*\)/\o033[92m\1\o033[39m/' \
                -e 's/\(.*false.*\)/\o033[31m\1\o033[39m/' \
                -e 's/\(.*alive_compute_threshold.*\)/\o033[33m\1\o033[39m/' \
                -e 's/\(.*dead_compute_threshold.*\)/\o033[33m\1\o033[39m/'
}

#clear
Check_openrc_file

source $OPENRC_PATH
nova_state_list=$(openstack compute service list)
comp_and_ctrl_nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)|(nova-scheduler)" | awk '{print $6}')
ctrl_node=$(echo "$nova_state_list" | grep -E "(nova-scheduler)" | awk '{print $6}')
for i in $ctrl_node; do ctrl_node_array+=("$i"); done;

Check_nova_srvice_list
Check_connection_to_nova_nodes
Check_disabled_computes_in_nova
Check_docker_consul
Check_members_list
Check_consul_logs
Check_consul_config