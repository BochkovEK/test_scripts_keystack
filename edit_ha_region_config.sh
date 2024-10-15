# The script for change or check consul log
# openrc file required in $HOME/ for getting region name
# Start scrip to change alive_threshold in consul conf: bash edit_ha_region_config.sh -a 2

#ctrl_pattern="\-ctrl\-..$"
service_name=consul
#consul_conf_dir=kolla/$service_name
test_node_conf_dir=kolla/$service_name
conf_dir=/etc/kolla/$service_name
script_dir=$(dirname $0)
utils_dir="$script_dir/utils"
#get_nodes_list_script="get_nodes_list.sh"
install_package_script="install_package.sh"

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $ALIVE_THRSHOLD ]] && ALIVE_THRSHOLD=""
[[ -z $DEAD_THRSHOLD ]] && DEAD_THRSHOLD=""
[[ -z $IPMI_FENCING ]] && IPMI_FENCING=""
[[ -z $NOVA_FENCING ]] && NOVA_FENCING=""
[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $CHECK_SUFFIX ]] && CHECK_SUFFIX="false"
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK="false"
[[ -z $PUSH ]] && PUSH="false"
[[ -z $PULL ]] && PULL="false"
[[ -z $CONF_NAME ]] && CONF_NAME=""

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

        -a,   -alive_threshold          <alive_compute_threshold>
        -d,   -dead_threshold           <dead_compute_threshold>
        -i,   -ipmi_fencing             <true\false>
        -n,   -nova_fencing             <true\false>
        -v,   -debug                    without value, set DEBUG=\"true\"
        -pull                           without value, pull region-config_<region_name>.json from
                                        /etc/kolla/consul/region-config_<region_name>.json on ctrl node to
                                        $script_dir/$test_node_conf_dir
        -push                           without value, push region-config_<region_name>.json from
                                        $script_dir/$test_node_conf_dir to
                                        /etc/kolla/consul/region-config_<region_name>.json on ctrl nodes
       -check                          only check option (without parameter)


        start script with parameter suffix: bash edit_ha_region_config.sh suffix - return bmc suffix
        start script with parameter suffix: bash edit_ha_region_config.sh check  - return contents of the config file
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
        -n|-nova_fencing) NOVA_FENCING="$2"
          echo "Found the -nova_fencing <true\false> option, with parameter value $NOVA_FENCING"
          shift ;;
        -v|-debug) DEBUG="true"
	        echo "Found the -debug, parameter set $DEBUG"
          ;;
        -pull) PULL="true"
	        echo "Found the -pull, parameter set $PULL"
          ;;
        -push) PUSH="true"
	        echo "Found the -push, parameter set $PUSH"
          ;;
        -check) ONLY_CONF_CHECK="true"
	        echo "Found the -check, parameter set $ONLY_CONF_CHECK"
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

Check_openrc_file () {
    echo "Check openrc file here: $OPENRC_PATH"
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    #echo $OPENRC_PATH
    #echo $check_openrc_file
    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
}

cat_conf () {
  echo "Cat all $service_name configs..."
  bash $script_dir/command_on_nodes.sh -nt ctrl -c "echo \"cat $conf_dir/region-config_${REGION}.json\"; cat $conf_dir/region-config_${REGION}.json"
}

pull_conf () {
  echo "Check and create folder $test_node_conf_dir in $script_dir folder"
  [ ! -d $script_dir/$test_node_conf_dir ] && { mkdir -p $script_dir/$test_node_conf_dir; }
#  echo "ctrl_pattern: $ctrl_pattern"
  echo "Try parse /etc/hosts to find ctrl node..."
#  ctrl_node=$(cat /etc/hosts | grep -m 1 -E ${ctrl_pattern} | awk '{print $1}')
  nova_state_list=$(openstack compute service list)
  ctrl_node=$(echo "$nova_state_list" | grep -m 1 -E "nova-scheduler" | awk '{print $6}')
  echo "Pull consul conf from $ctrl_node:$conf_dir/region-config_${REGION}.json"
  scp -o StrictHostKeyChecking=no $ctrl_node:$conf_dir/region-config_${REGION}.json $script_dir/$test_node_conf_dir
}

push_conf () {
  [ -z $CONF_NAME ] && { CONF_NAME=region-config_${REGION}.json; }
  nova_state_list=$(openstack compute service list)
  ctrl_nodes=$(echo "$nova_state_list" | grep -E "nova-scheduler" | awk '{print $6}')
#  ctrl_nodes=$(cat /etc/hosts | grep -E ${ctrl_pattern} | awk '{print $1}')
  [ "$DEBUG" = true ] && { for string in $ctrl_nodes; do debug_echo $string; done; }
  if ! bash $utils_dir/$install_package_script host; then
    exit 1
  fi

#  "bind_address": "10.224.132.178",

  for node in $ctrl_nodes; do
    ip=$(host $node|awk '{print $4}')
    [ "$DEBUG" = true ] && { debug_echo $ip; }
    echo "\"bind_address\": \"$ip\" on $CONF_NAME"
    sed -i --regexp-extended "s/\"bind_address\"(\s+|):\s+\"[0-9]+.[0-9]+.[0-9]+.[0-9]+\"\,/\"bind_address\": \"$node\",/" \
      $script_dir/$test_node_conf_dir/$CONF_NAME
    echo "Push consul conf to $node:$conf_dir/$CONF_NAME"
    scp -o StrictHostKeyChecking=no $script_dir/$test_node_conf_dir/$CONF_NAME $node:$conf_dir/$CONF_NAME
  done
}

change_alive_threshold () {
  echo "Changing alive threshold..."
  pull_conf
  sed -i --regexp-extended "s/\"alive_compute_threshold\":\s+\"[0-9]+\"/\"alive_compute_threshold\": \"$1\"/" \
   $script_dir/$test_node_conf_dir/region-config_${REGION}.json
  push_conf
  conf_changed="true"
}

change_dead_threshold () {
  echo "Changing dead threshold..."
  pull_conf
  dead_threshold_string_exist=$(cat $script_dir/$test_node_conf_dir/region-config_${REGION}.json| grep 'dead_compute_threshold')

  if [ -z "$dead_threshold_string_exist" ]; then
    alive_threshold_string=$(cat $script_dir/$test_node_conf_dir/region-config_${REGION}.json| grep 'alive_compute_threshold')

    sed -i --regexp-extended "s/$alive_threshold_string/${alive_threshold_string}\n   \"dead_compute_threshold\": \"$1\",/" \
    $script_dir/$test_node_conf_dir/region-config_${REGION}.json
  else
    sed -i --regexp-extended "s/\"dead_compute_threshold\":\s+\"[0-9]+\",/\"dead_compute_threshold\": \"$1\",/" \
      $script_dir/$test_node_conf_dir/region-config_${REGION}.json
  fi
  push_conf
#  cat_consul_conf
  conf_changed="true"
}

change_ipmi_fencing () {
  if [ "$1" = true ]; then
    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"bmc\": false/\"bmc\": true/' $conf_dir/region-config_${REGION}.json"
  elif [ "$1" = false ]; then
    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"bmc\": true/\"bmc\": false/' $conf_dir/region-config_${REGION}.json"
  else
    echo "$1 - is not valid ipmi parameter"
    return 1
  fi
  conf_changed="true"
}

change_nova_fencing () {
  if [ "$1" = true ]; then
    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"nova\": false/\"nova\": true/' $conf_dir/region-config_${REGION}.json"
  elif [ "$1" = false ]; then
    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"nova\": true/\"nova\": false/' $conf_dir/region-config_${REGION}.json"
  else
    echo "$1 - is not valid nova parameter"
    return 1
  fi
  conf_changed="true"
}

check_bmc_suffix () {
  pull_conf
  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  script_dir: $script_dir
  REGION: $REGION
  ${service_name}_conf_dir: $conf_dir
  "

  [ ! -f $script_dir/$test_node_conf_dir/region-config_${REGION}.json ] && { echo "Config exists in: $script_dir/$test_node_conf_dir/region-config_${REGION}.json"; pull_conf; }
  [ "$DEBUG" = true ] && { echo -e "[DEBUG]\n"; ls -la $script_dir; }
  [ ! -f $script_dir/$test_node_conf_dir/region-config_${REGION}.json ] && { echo "Config not found"; exit 1; }
  suffix_string_raw_1=$(cat $script_dir/$test_node_conf_dir/region-config_${REGION}.json|grep 'suffix')
  suffix_string_raw_2=${suffix_string_raw_1//\"/}
  echo "${suffix_string_raw_2%%,*}"|awk '{print $2}'
}


[ "$CHECK_SUFFIX" = true ] && { check_bmc_suffix; exit 0; }
[ "$PUSH" = true ] && { push_conf; conf_changed=true; }
[ "$PULL" = true ] && { pull_conf; exit 0; }
[ -n "$ALIVE_THRSHOLD" ] && change_alive_threshold $ALIVE_THRSHOLD
[ -n "$DEAD_THRSHOLD" ] && change_dead_threshold $DEAD_THRSHOLD
[ -n "$IPMI_FENCING" ] && change_ipmi_fencing $IPMI_FENCING
[ -n "$NOVA_FENCING" ] && change_nova_fencing $NOVA_FENCING
cat_conf
[ -n "$conf_changed" ] && { echo "Restart consul containers..."; bash $script_dir/command_on_nodes.sh -nt ctrl -c "docker restart consul"; }
[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }
