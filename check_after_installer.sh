#!/bin/bash

#The script check python, virtual flags on nodes

#!!! needed Check container list

required_python="python:3.8"
cmpt_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"
required_container_list=(
#"bifrost_deploy"
#"netbox-housekeeping"
"netbox-worker"
"netbox"
"netbox-redis"
"netbox-postgres"
"netbox-redis-cache"
"gitlab-runner"
"gitlab"
"vault"
"nginx"
"nexus"
)
#"web"


nodes_to_find="$cmpt_pattern|$ctrl_pattern|$net_pattern"
echo "nodes_to_find: $nodes_to_find"

#color
red=$(tput setaf 1)
green=$(tput setaf 2)
normal=$(tput sgr0)


print_end () {
    echo -e "\n======== End checking - ${green}SUCCEED!${normal} ========\n"
}

print_end_fail () {
    echo -e "\n========== End checking - ${red}FAIL${normal} ==========\n"
    exit 1
}

print_fail () {
        echo -e "${red}${1} - FAIL${normal}"
        print_end_fail
}

print_ok () {
        echo -e "${green}${1} - OK!${normal}"
}

# for compare need: package_requair, package_exist
# package_requair format: <package_name>:<version>
compare_version () {
    required_version=$(echo ${1} | awk -F ':' '{print $2}')
#    echo required_version $required_version

    current_version=$(echo ${2} | awk -F ':' '{print $2}')
#    echo current_version $current_version

    integer_part_req_ver=$(echo ${required_version} | awk -F '.' '{print $1}')
#    echo integer_part_req_ver $integer_part_req_ver
    fractional_part_req_ver=$(echo ${required_version} | awk -F '.' '{print $2}')
#    echo fractional_part_req_ver $fractional_part_req_ver

    integer_part_curr_ver=$(echo ${current_version} | awk -F '.' '{print $1}')
#    echo integer_part_curr_ver $integer_part_curr_ver
    fractional_part_curr_ver=$(echo ${current_version} | awk -F '.' '{print $2}')
#    echo fractional_part_curr_ver $fractional_part_curr_ver

    if ((integer_part_curr_ver > integer_part_req_ver)); then
        print_ok "${2}"
    elif ((integer_part_curr_ver == integer_part_req_ver)); then
        if ((fractional_part_curr_ver >= fractional_part_req_ver)); then
            print_ok ${2}
        else
            print_fail "${2} package version older then requaired (${1})"
        fi
    else
         print_fail "${2} package version older then requaired (${1})"
    fi
}

check_python () {
# ${1}: "python:3.7.2"
    py_main_ver=$(echo ${1} | grep -o -E ':[0-9]+')
    py_main_ver=${py_main_ver:1}

    package_exist=$(ssh -o StrictHostKeyChecking=no $2 python${py_main_ver} --version 2>/dev/null)
# Example output: Python 3.5.2
    if [[ ! -z ${package_exist} ]]; then
       curr_pack_name=$(echo ${package_exist// /:})
       compare_version ${1} $curr_pack_name
    else
       print_fail "Required ${1} package is missing - ${red}FAIL${normal}"
    fi
}

check_virt_flags () {
    host_name=$(ssh -o StrictHostKeyChecking=no $1 hostname 2>/dev/null)
    echo "Check virtualiztion flag on $host_name..."
    virt_flag=$(ssh -o StrictHostKeyChecking=no $1 "egrep '(vmx|svm)' /proc/cpuinfo 2>/dev/null")
    if [[ ! -z ${virt_flag} ]]; then
       print_ok "virtualization flag exists on $host_name"
    else
       print_fail "virtualization flag does't exists on $host_name"
    fi
}

check_container_on_lcm () {
  echo "Check container list on lcm"
  container_name_on_lcm=$(docker ps --format "{{.Names}}" --filter status=running)
  for container_requaired in "${required_container_list[@]}"; do
    container_exist="false"
    for container in $container_name_on_lcm; do
#      echo "$container" - "$container_requaired"
      if [ "$container" = "$container_requaired" ]; then
        container_exist="true"
#      else
#        container_exist="false"
#        print_fail "$container not found"
      fi
    done
    if [ "$container_exist" = "true" ]; then
      container_exist="true"
      print_ok "$container_requaired"
    else
      print_fail "$container_requaired not found"
    fi
  done
}

check_container_on_lcm

srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}')
for host in $srv; do
    echo "Check $host node..."
    #cmpt_pattern_clip="${cmpt_pattern#*|}"
    #echo $cmpt_pattern_clip
    cmpt_node=$(ssh -o StrictHostKeyChecking=no $host "hostname| grep -E '${cmpt_pattern}' 2>/dev/null")
    echo "$cmpt_node"
    if [[ -n ${cmpt_node} ]]; then
        check_virt_flags $host
    fi
    echo "Check python on $(cat /etc/hosts | grep -E ${host} | awk '{print $2}')"
    check_python $required_python $host
done
