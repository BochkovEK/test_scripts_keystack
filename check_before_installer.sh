#!/bin/bash

# Script checklist:
# - Required packages
# - Docker status
# - Check compose.yaml file by docker-compose
# - Check Timezone???

# Required package names must be in the following format:
# "<packege-name>:<num>.<num>"
#
# Python packages are specified in a variable: required_python
# docker compose pluggin are specified in a variable: required_docker_compose
# RPM packages LIST are specified in a variable: required_rpm
#
# Example:
# required_python="python:3.6"
# required_docker_compose="docker-compose:2.1"
# required_rpm=(
#    bash:4.0
#    )

#=================== VARIABLES ======================
COMPOSE_FILE=~/installer/compose.yaml
SETTINGS_FILE=./installer/source

red=$(tput setaf 1)
green=$(tput setaf 2)
normal=$(tput sgr0)

#----- test env -----
export LCM_IP=10.0.0.10
export DOMAIN=test.env.keystack.click
export INSTALL_DIR=/root/installer
export BACKUP_HOME=/installer/backup
export INSTALL_HOME=/installer
export CFG_HOME=/installer/config
export REPO_HOME=/installer/repo
export CA_HOME=/installer/data/ca
export PORTAINER_HOME=/installer/data/portainer
export GITLAB_HOME=/installer/data/gitlab
export GITLAB_RUNNER_HOME=/installer/data/gitlab-runner
export WEB_HOME=/installer/data/web
export LOGS_HOME=/installer/data/logs
export NEXUS_HOME=/installer/data/nexus
export VAULT_HOME=/installer/data/vault
export SSL_CERT_FILE=/installer/data/ca/installer/certs/chain-ca.pem
#--- end test env ---

[[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })

case $os in
    ditmosos-kolchak)
        docker_compose_command="docker-compose"
        required_docker_compose="docker-compose:1.29"
        required_python="python:3.6"
        required_rpm=(
            sudo:1.0
            bash:4.0
            openssl:1.1
            git-core:2.30
            curl:5.0
            tar:1.0
            jq:1.5
            python3-pip:8.0
            docker:20.0
        )
    ;;
    *)
        docker_compose_command="docker compose"
        required_python="python:3.6"
        required_docker_compose="docker-compose:2.10"
        required_rpm=(
            #test_pkg:1
            sudo:1.0
            bash:2.0
            openssl:1.1
            git:2.30
            curl:5.0
            tar:1.0
            jq:1.5
            python3-pip:8.0
            docker-ce:20.0
        )
    ;;
esac

#=================== FUNCTIONS ======================

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

unset_source_test () {
    unset LCM_IP \
          DOMAIN \
          INSTALL_DIR \
          BACKUP_HOME \
          INSTALL_HOME \
          CFG_HOME \
          REPO_HOME \
          CA_HOME \
          PORTAINER_HOME \
          GITLAB_HOME \
          GITLAB_RUNNER_HOME \
          WEB_HOME \
          LOGS_HOME \
          NEXUS_HOME \
          VAULT_HOME \
          SSL_CERT_FILE
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

check_rpm_packages () {

    for package in "${required_rpm[@]}"; do
#        echo package $package
        package_name=$(echo $package | awk -F ":" '{print $1}')
#        echo package_name $package_name
         package_exist=$(rpm -q --qf "%{NAME}:%{VERSION}" ${package_name})
         package_not_installed=$(echo $package_exist | grep 'not installed')
#        echo package_exist $package_exist
        if [[ ! -z ${package_not_installed} ]]; then
            print_fail "Required ${package} package is missing"
        else
            compare_version $package $package_exist
        fi
    done
}

check_dpkg_packages () {
    packages=("$@")
    for package in "${packages[@]}"; do
#        echo package $package
        package_name=$(echo $package | awk -F ":" '{print $1}')
#        echo package_name: $package_name
        package_exist_version=$(dpkg -l|grep $package_name| awk '{print $3}')
#        package_exist_version=$(apt-cache show $package_name|grep "Version:"|head -1 | awk '{print $2}')
#       echo package $package_name: $package_exist_version
        package_exist_version=${package_exist_version#*:}
        package_exist_version=${package_exist_version%%-*}
        package_exist_version=${package_exist_version%%+*}
        package_exist_version=${package_exist_version%%~*}

        if [[ -z ${package_exist_version} ]]; then
            print_fail "Required ${package_name} package is missing"
        else
            package_exist=$(echo "$package_name:$package_exist_version")
#            echo package_exist: $package_exist
            compare_version $package $package_exist
        fi
    done
}

check_python () {

# ${1}: "python:3.7.2"
    py_main_ver=$(echo ${1} | grep -o -E ':[0-9]+')
    py_main_ver=${py_main_ver:1}

    package_exist=$(python${py_main_ver} --version 2>/dev/null)
# Example output: Python 3.5.2
    if [[ ! -z ${package_exist} ]]; then
       curr_pack_name=$(echo ${package_exist// /:})
       compare_version ${1} $curr_pack_name
    else
       print_fail "Required ${1} package is missing - ${red}FAIL${normal}"
    fi
}

check_docker_compose () {

# ${1}: "docker-compose:2.11"
#    echo $docker_compose_command
    package_exist=$(${docker_compose_command} version 2>/dev/null | \
      grep -i "^${docker_compose_command}")
#    echo package_exist $package_exist
# Example output: Docker compose v2.15.1
    if [[ ! -z ${package_exist} ]]; then
        curr_docker_pack_name=$(echo $package_exist | sed "s/ Compose version v/-compose:/g" | \
          sed "s/ version /:/g")
#        echo curr_docker_pack_name $curr_docker_pack_name
        curr_docker_pack_name=$(echo $curr_docker_pack_name | grep -o -iE "docker-compose:[0-9]+.[0-9]+")
#        echo curr_docker_pack_name $curr_docker_pack_name
        compare_version ${1} $curr_docker_pack_name
    else
        print_fail "Required ${1} package is missing - ${red}FAIL${normal}"
    fi
}

check_docker_status () {

    status_docker=$(systemctl status docker | grep "Active: active (running)")
#    echo "Docker status: "$status_docker

    if [ -z "$status_docker" ]; then
        print_fail "Docker is NOT running"
        print_end_fail
    else
        print_ok "Docker is active (running)"
    fi
}

check_docker_compose_file () {

#    source $SETTINGS_FILE
    #check_comp_file=$(
    ${docker_compose_command} -f $COMPOSE_FILE config
    #)

    if [ $? -eq 0 ]; then
        print_ok "Docker compose file ($COMPOSE_FILE)"
#        rm $COMPOSE_FILE
        unset_source_test
    else
        print_fail "Docker compose file ($COMPOSE_FILE)"
        unset_source_test
        print_end_fail
    fi
}

check_timezone () {

    timedatectl set-timezone Europe/Moscow
    if [ $? -eq 0 ]; then
        print_ok "Time zone status"
    else
        print_fail "Time zone status"
        print_end_fail
    fi
}

#===================== MAIN =========================

clear
echo -e "\n====== Insatlled packages checking ======\n"
case $os in
    ubuntu)
        check_dpkg_packages "${required_rpm[@]}"
    ;;
    *)
        check_rpm_packages
    ;;
esac

echo -e "\n============ Python checking ============\n"
check_python $required_python

echo -e "\n======== Docker compose checking ========\n"
check_docker_compose $required_docker_compose

echo -e "\n======== Docker status checking =========\n"
check_docker_status

echo -e "\n===== compose.yaml syntax checking ======\n"
check_docker_compose_file

echo -e "\n========== Time zone checking ===========\n"
check_timezone

print_end

