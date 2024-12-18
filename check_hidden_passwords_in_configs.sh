#!/bin/bash

# The script check configs by list on controls nodes and find group [castellan_configsource]

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 13)
cyan=$(tput setaf 14)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
#magenta=$(tput setaf 5)

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

command_on_nodes_script_name="command_on_nodes.sh"

control_config_list=(
  "/etc/kolla/keystone/keystone.conf"
  "/etc/kolla/glance-api/glance-api.conf"
  "/etc/kolla/cinder-volume/cinder.conf"
  "/etc/kolla/neutron-server/neutron.conf"
  "/etc/kolla/drs/drs.ini"
  "/etc/kolla/placement-api/placement.conf"
  "/etc/kolla/adminui-backend/adminui-backend-osloconf.conf"
  "/etc/kolla/adminui-backend/adminui-backend-regions.conf"
)

compute_config_list=(
  "/etc/kolla/nova-compute/nova.conf"
)

hashed_password_config_list=(
  "/etc/kolla/haproxy/services.d/opensearch-dashboards.cfg"
  "/etc/kolla/rabbitmq/definitions.json"
  "/etc/kolla/proxysql/users/*"
  "/etc/kolla/haproxy/services.d/prometheus-alertmanager.cfg"
)

prometheus_exporters_config_list=(
  "/etc/kolla/prometheus-mysqld-exporter/my.cnf"
  "/etc/kolla/prometheus-rabbitmq-exporter/prometheus-rabbitmq-config.json"
  "/etc/kolla/prometheus-openstack-exporter/clouds.yml"
)

[[ -z $CHECK_COMP ]] && CHECK_COMP="false"
[[ -z $CHECK_CTRL ]] && CHECK_CTRL="false"
[[ -z $CHECK_HASHED ]] && CHECK_HASHED="false"
[[ -z $CHECK_PROMETH ]] && CHECK_PROMETH="false"
[[ -z $CHECK_ALL ]] && CHECK_ALL="true"
#[[ -z $DEBUG ]] && DEBUG="false"

# Define parameters
define_parameters () {
  [ "$DEBUG" = true ] && echo "[DEBUG]: \"\$1\": $1"
#  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
#  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
}

count=1
while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -comp                       check configs on comp nodes ${compute_config_list[*]}
      -ctrl                       check configs on ctrl nodes ${control_config_list[*]}
      -hashed                     check hashed passwords on configs ${hashed_password_config_list[*]}
      -prometheus                 check prometheus exporters configs ${prometheus_exporters_config_list[*]}
"
      exit 0
      break ;;
    -comp) CHECK_COMP=true; CHECK_ALL="false"
      echo "Found the -comp. Check configs on comp nodes ${compute_config_list[*]}"
      shift ;;
    -ctrl) CHECK_CTRL=true; CHECK_ALL="false"
      echo "Found the -ctrl. Check configs on ctrl nodes ${control_config_list[*]}"
      shift ;;
    -hashed) CHECK_HASHED=true; CHECK_ALL="false"
      echo "Found the -hashed. Check hashed passwords on configs ${hashed_password_config_list[*]}"
      shift ;;
    -prometheus) CHECK_PROMETH=true; CHECK_ALL="false"
      echo "Found the -prometheus. Check prometheus exporters configs ${prometheus_exporters_config_list[*]}"
      shift ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
  esac
  shift
done

# Check script exists
if [ ! -f $script_dir/$command_on_nodes_script_name ]; then
  printf "%s\n" "${red}Script: $command_on_nodes_script_name does not exists - error${normal}"
  exit 0
fi

read_conf () {
  bash $script_dir/$command_on_nodes_script_name -nt $1 -c "ls -f $2" | \
    sed --unbuffered \
      -e 's/\(.*\No such file or directory.*\)/\o033[31m\1 - ok\o033[39m/'
  if [ "$3" = castellan ]; then
    bash $script_dir/$command_on_nodes_script_name -nt $1 -c "cat $2 | grep -E 'db_uri|password|\[castellan_configsource\]'| \
      sed --unbuffered \
        -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - [ok: castellan group exists]\o033[39m/'\
        -e 's/\(.*password.*\)/\o033[33m\1 - [Warning: check password]\o033[33m/'"
  fi
  if [ "$4" = cat ]; then
    bash $script_dir/$command_on_nodes_script_name -nt $1 -c "cat $2"
  fi

}

Check_configs_on_controls () {
  echo -E "${cyan}Check '[castellan_configsource]' in configs on control${normal}"
  export DONT_CHECK_CONN=true
  for config in "${control_config_list[@]}"; do
    echo -E "${violet}Check control config: $config${normal}"
    read_conf ctrl $config castellan
#    bash $command_on_nodes_script_name -nt ctrl -c "cat $config | grep -E 'password|\[castellan_configsource\]'| \
#          sed --unbuffered \
#            -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - ok\o033[39m/' \
#            -e 's/\(.*\No such file or directory.*\")/\o033[31m\1 - ok\o033[39m/'"
  done
  export DONT_CHECK_CONN=""
}

Check_configs_on_computes () {
  echo -E "${cyan}Check '[castellan_configsource]' in configs on computes${normal}"
  export DONT_CHECK_CONN=true
  for config in "${compute_config_list[@]}"; do
    echo -E "${violet}Check computes config: $config${normal}"
    read_conf comp $config castellan
#    bash $command_on_nodes_script_name -nt comp -c "cat $config | grep '\[castellan_configsource\]'| \
#          sed --unbuffered \
#            -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - ok\o033[39m/' \
#            -e 's/\(.*\No such file or directory.*\")/\o033[31m\1 - ok\o033[39m/'"
  done
  export DONT_CHECK_CONN=""
}

Check_config_with_hashed_password () {
  echo -E "${cyan}Check config with hashed password${normal}"
  export DONT_CHECK_CONN=true
  for config in "${hashed_password_config_list[@]}"; do
    echo -E "${violet}Check control config: $config${normal}"
    read_conf ctrl $config castellan
#    bash $script_dir/$command_on_nodes_script_name -nt ctrl -c "cat $config | grep 'password'"
  done
  export DONT_CHECK_CONN=""
}

Check_hidden_passwords_in_prometheus_exporters () {
  echo -E "${cyan}Check hidden passwords in prometheus exporters${normal}"
  export DONT_CHECK_CONN=true
  for config in "${prometheus_exporters_config_list[@]}"; do
    echo -E "${violet}Check control config: $config${normal}"
    read_conf ctrl $config foo cat
#    bash $script_dir/$command_on_nodes_script_name -nt ctrl -c "cat $config"
    # | grep 'password'"
  done
  export DONT_CHECK_CONN=""
}


if [ "$CHECK_COMP" = true ] || [ "$CHECK_ALL" = true ]; then
  Check_configs_on_computes
fi
if [ "$CHECK_CTRL" = true ] || [ "$CHECK_ALL" = true ]; then
  Check_configs_on_controls
fi
if [ "$CHECK_HASHED" = true ] || [ "$CHECK_ALL" = true ]; then
  Check_config_with_hashed_password
fi
if [ "$CHECK_PROMETH" = true ] || [ "$CHECK_ALL" = true ]; then
  Check_hidden_passwords_in_prometheus_exporters
fi