# The script change alive_threshold in consul region config
# openrc file required in ~/
# Start scrip: bash ha_region_config.sh -a 2

ctrl_pattern="\-ctrl\-..$"
consul_conf_dir=kolla/consul

script_dir=$(dirname $0)

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $ALIVE_THRSHOLD ]] && ALIVE_THRSHOLD=""
[[ -z $DEAD_THRSHOLD ]] && DEAD_THRSHOLD=""
[[ -z $IPMI_FENCING ]] && IPMI_FENCING=""
[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $CHECK_SUFFIX ]] && CHECK_SUFFIX="false"
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK="false"

#[[ -z "${1}" ]] && { echo "Alive threshold value required as parameter script"; exit 1; }

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [ "$1" = suffix ] && { CHECK_SUFFIX=true; echo "Check suffix parameter found"; }
  [ "$count" = 1 ] && [ "$1" = check ] && { ONLY_CONF_CHECK=true; echo "Only conf check parameter found"; }
}

count=1
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The script change consul region config
        openrc file required in ~/

        -a,   -alive_threshold          <alive_threshold>
        -d,   -dead_compute_threshold   <dead_compute_threshold>
        -i,   -ipmi_fencing             <true\false>

        start script with parameter suffix: bash ha_region_config.sh suffix - return bmc suffix
        "
          exit 0
          break ;;
	      -a|-alive_threshold) ALIVE_THRSHOLD="$2"
	        echo "Found the -alive_threshold <alive_threshold> option, with parameter value $ALIVE_THRSHOLD"
          shift ;;
        -d|-dead_threshold) DEAD_THRSHOLD="$2"
	        echo "Found the -dead_threshold <dead_threshold> option, with parameter value $DEAD_THRSHOLD"
          shift ;;
        -i|-ipmi_fencing) IPMI_FENCING="$2"
          echo "Found the -ipmi_fencing <true\false> option, with parameter value $IPMI_FENCING"
          shift ;;
        -v|-debug) DEBUG="true"
	        echo "Found the -debug, with parameter value $DEBUG"
          ;;
        --) shift
          break ;;
        *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
        esac
        shift
done

source $OPENRC_PATH
REGION=$OS_REGION_NAME
[[ -z "${REGION}" ]] && { echo "Region name not found"; exit 1; }

debug_echo () {
  echo "[DEBUG] \$1: $1"
}

Check_openrc_file () {
    echo "Check openrc file here: $OPENRC_PATH"
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    #echo $OPENRC_PATH
    #echo $check_openrc_file
    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
}

#Check_connection_to_ipmi () {
#  check_openrc_file
#  source $OPENRC_PATH
#  nova_state_list=$(openstack compute service list)
#  comp_nodes=$(echo "$nova_state_list" | grep -E "(nova-compute)" | awk '{print $6}')
#  for host in $comp_nodes; do
##   host $host
#    sleep 1
#    if ping -c 2 $host$suffix &> /dev/null; then
#      printf "%40s\n" "${green}There is a connection with $host$suffix - success${normal}"
#    else
#      printf "%40s\n" "${red}No connection with $host$suffix - error!${normal}"
#      echo -e "${red}The node may be turned off.${normal}\n"
#    fi
#  done
#}

cat_consul_conf () {
  echo "Cat all consul configs..."
  bash $script_dir/command_on_nodes.sh -nt ctrl -c "echo \"cat /etc/kolla/consul/region-config_${REGION}.json\"; cat /etc/kolla/consul/region-config_${REGION}.json"
}

pull_consul_conf () {
  [ ! -d $consul_conf_dir ] && { mkdir -p $consul_conf_dir; }
  ctrl_node=$(cat /etc/hosts | grep -m 1 -E ${ctrl_pattern} | awk '{print $2}')
  [ "$DEBUG" = true ] && debug_echo $ctrl_node

  echo "Сopying consul conf from $ctrl_node:/etc/kolla/consul/region-config_${REGION}.json"
  scp -o StrictHostKeyChecking=no $ctrl_node:/etc/kolla/consul/region-config_${REGION}.json $consul_conf_dir
}

push_consul_conf () {
  ctrl_nodes=$(cat /etc/hosts | grep -E ${ctrl_pattern} | awk '{print $2}')
  [ "$DEBUG" = true ] && { for string in $ctrl_nodes; do debug_echo $string; done; }
  for node in $ctrl_nodes; do
    echo "Сopying consul conf to $node:/etc/kolla/consul/region-config_${REGION}.json"
    scp -o StrictHostKeyChecking=no ${consul_conf_dir}/region-config_${REGION}.json $node:/etc/kolla/consul/region-config_${REGION}.json
  done
}

change_alive_threshold () {
  pull_consul_conf
  sed -i --regexp-extended "s/\"alive_compute_threshold\":\s+\"[0-9]+\"/\"alive_compute_threshold\": \"$1\"/" \
   ${consul_conf_dir}/region-config_${REGION}.json
  push_consul_conf
#  cat_consul_conf
  conf_id_changed="true"
}

change_dead_threshold () {
  pull_consul_conf
  dead_threshold_string_exist=$(cat ${consul_conf_dir}/region-config_${REGION}.json| grep 'dead_compute_threshold')
  [ "$DEBUG" = true ] && debug_echo "${dead_threshold_string_exist}"
  if [ -z "$dead_threshold_string_exist" ]; then
    alive_threshold_string=$(cat ${consul_conf_dir}/region-config_${REGION}.json| grep 'alive_compute_threshold')
    [ "$DEBUG" = true ] && debug_echo "${alive_threshold_string}"
    sed -i --regexp-extended "s/$alive_threshold_string/${alive_threshold_string}\n   \"dead_compute_threshold\": \"$1\",/" \
    ${consul_conf_dir}/region-config_${REGION}.json
  else
    sed -i --regexp-extended "s/\"dead_compute_threshold\":\s+\"[0-9]+\",/\"dead_compute_threshold\": \"$1\",/" \
      ${consul_conf_dir}/region-config_${REGION}.json
  fi
  push_consul_conf
#  cat_consul_conf
  conf_id_changed="true"
}

change_ipmi_fencing () {
  if [ "$1" = true ]; then
    bash command_on_nodes.sh -nt ctrl -c "sed -i 's/\"bmc\": false/\"bmc\": true/' /etc/kolla/consul/region-config_${REGION}.json"
  elif [ "$1" = false ]; then
    bash command_on_nodes.sh -nt ctrl -c "sed -i 's/\"bmc\": true/\"bmc\": false/' /etc/kolla/consul/region-config_${REGION}.json"
  else
    echo "$1 - is not valid ipmi parameter"
    return 1
  fi
  conf_id_changed="true"
}

check_bmc_suffix () {
  pull_consul_conf
  [ ! -f $script_dir/$consul_conf_dir/region-config_${REGION}.json ] && { echo "Config exists in: $script_dir/$consul_conf_dir/region-config_${REGION}.json"; pull_consul_conf; }
  [ ! -f $script_dir/$consul_conf_dir/region-config_${REGION}.json ] && { echo "Config not found"; exit 1; }
  suffix_string_raw_1=$(cat $consul_conf_dir/region-config_${REGION}.json|grep 'suffix')
  suffix_string_raw_2=${suffix_string_raw_1//\"/}
  echo "${suffix_string_raw_2%%,*}"|awk '{print $2}'
}

only_conf_check () {
  pull_consul_conf
  cat_consul_conf
}

[ "$CHECK_SUFFIX" = true ] && { check_bmc_suffix; exit 0; }
[ "$ONLY_CONF_CHECK" = true ] && { only_conf_check; exit 0; }
##pull_consul_conf
[ -n "$ALIVE_THRSHOLD" ] && change_alive_threshold $ALIVE_THRSHOLD
[ -n "$DEAD_THRSHOLD" ] && change_dead_threshold $DEAD_THRSHOLD
[ -n "$IPMI_FENCING" ] && change_ipmi_fencing $IPMI_FENCING
cat_consul_conf
[ -n "$conf_id_changed" ] && { echo "Restart consul containers..."; bash command_on_nodes.sh -nt ctrl -c "docker restart consul"; }
##cat_consul_conf