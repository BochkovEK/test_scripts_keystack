#!/bin/bash

required_python="python:3.8"
nodes_to_find="\-ctrl\-..$|\-comp\-..$|\-net\-..$"

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

srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}')
for host in $srv; do
        echo "Check python on $(cat /etc/hosts | grep -E ${host} | awk '{print $2}')"
         check_python $required_python $host
done
