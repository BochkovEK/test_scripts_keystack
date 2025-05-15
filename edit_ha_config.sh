# The script for edit HA conf
# To start: bash ~/test_scripts_keystack/edit_ha_config.sh --help

#ctrl_pattern="\-ctrl\-..$"
service_name=consul
nodes_type="ctrl"
test_node_conf_dir=kolla/$service_name
conf_dir=/etc/kolla/$service_name
conf_name="ha-config.ini"
script_dir=$(dirname "$0")
script_name=$(basename "$0")
utils_dir="$script_dir/utils"
check_openrc_script="check_openrc.sh"
get_nodes_list_script="get_nodes_list.sh"
default_user="root"
#install_package_script="install_package.sh"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
#[[ -z $ALIVE_THRSHOLD ]] && ALIVE_THRSHOLD=""
#[[ -z $DEAD_THRSHOLD ]] && DEAD_THRSHOLD=""
#[[ -z $IPMI_FENCING ]] && IPMI_FENCING=""
#[[ -z $NOVA_FENCING ]] && NOVA_FENCING=""
[[ -z $CHECK_SUFFIX ]] && CHECK_SUFFIX="false"
[[ -z $TS_DEBUG ]] && DEBUG="false"
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK="false"
[[ -z $PUSH ]] && PUSH="false"
[[ -z $PULL ]] && PULL="false"
[[ -z $LEGACY_CONF ]] && LEGACY_CONF="false"
[[ -z $CONF_NAME ]] && CONF_NAME=$conf_name
[[ -z $OS_REGION_NAME ]] && OS_REGION_NAME=""
[[ -z $GET_CONFIG_PATH ]] && GET_CONFIG_PATH="false"
[[ -z $USER ]] && USER="$default_user"


#[[ -z "${1}" ]] && { echo "Alive threshold value required as parameter script"; exit 1; }

# Define parameters
define_parameters () {
#  pass
  [ "$count" = 1 ] && [ "$1" = suffix ] && { CHECK_SUFFIX=true; echo "Check suffix parameter found"; }
  [ "$count" = 1 ] && [ "$1" = config_path ] && { GET_CONFIG_PATH=true; echo "Get config path parameter found"; }
#  [ "$count" = 1 ] && [ "$1" = check ] && { ONLY_CONF_CHECK=true; echo "Only conf check parameter found"; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      The script change consul region config

        -v, -debug    without value, set DEBUG=\"true\"
        -pull         pull consul config from ctrl node to $script_dir/$test_node_conf_dir
                      $script_dir/$test_node_conf_dir to
        -push         push consul config from $script_dir/$test_node_conf_dir to all ctrl nodes
        -check        only check option
        -l, legacy    edit legacy consul region config; work with -push, -pull, -check keys
        -u, user      set user for ssh access

      Note:
        In case of legacy versions of consul, to change the config you need to:
          1) Specify the key -l; -legacy
          2) Define the global variable OS_REGION_NAME, or add a file ~/openrc containing it
          Example command: bash ~/test_scripts_keystack/$service_name -check -l
      "
#      -push        without value, push region-config_<region_name>.json from
#     region-config_<region_name>.json from
#                   /etc/kolla/consul/region-config_<region_name>.json on ctrl node to
#        start script with parameter suffix: bash edit_ha_region_config.sh check  - return contents of the config file
#        start script with parameter suffix: bash edit_ha_region_config.sh suffix - return bmc suffix
#        openrc file required in ~/
#        -a,   -alive_threshold          <alive_compute_threshold>
#        -d,   -dead_threshold           <dead_compute_threshold>
#        -i,   -ipmi_fencing             <true\false>
#        -n,   -nova_fencing             <true\false>
      exit 0
      break ;;
#	      -a|-alive_threshold) ALIVE_THRSHOLD="$2"
#	        echo "Found the -alive_threshold <alive_threshold> option, with parameter value $ALIVE_THRSHOLD"
#          shift ;;
#        -d|-dead_threshold) DEAD_THRSHOLD="$2"
#	        echo "Found the -dead_threshold <dead_threshold> option, with parameter value $DEAD_THRSHOLD"
#          shift ;;
#        -i|-ipmi_fencing) IPMI_FENCING="$2"
#          echo "Found the -ipmi_fencing <true\false> option, with parameter value $IPMI_FENCING"
#          shift ;;
#        -n|-nova_fencing) NOVA_FENCING="$2"
#          echo "Found the -nova_fencing <true\false> option, with parameter value $NOVA_FENCING"
#          shift ;;
    -v|-debug) DEBUG="true"
      echo "Found the -debug, parameter set $TS_DEBUG"
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
    -l|-legacy) LEGACY_CONF="true"
      echo "Found the -legacy, parameter set $LEGACY_CONF"
      ;;
    -u|-user) USER="$2"
      USER_STR="-u $USER"
      echo "Found the -user parameter with value $USER"
      shift
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done

#source $OPENRC_PATH


#Check_openrc_file () {
#    echo "Check openrc file here: $OPENRC_PATH"
#    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
#    #echo $OPENRC_PATH
#    #echo $check_openrc_file
#    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
#}

#debug echo
debug_echo () {
  echo -e "
  [DEBUG]:
    $1"
}

# Check openrc file
check_and_source_openrc_file () {
  echo -e "${violet}Check openrc file...${normal}"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    echo -e "${green}$openrc_file file exist - success${normal}"
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    echo -e "${red}openrc file not found in $openrc_file${normal} - ERROR"
    exit 1
  fi
}

cat_conf () {
  echo "Cat all $service_name configs..."
  bash $script_dir/command_on_nodes.sh $USER_STR -nt $nodes_type -c "sudo sh -c 'echo \"cat $conf_dir/$CONF_NAME\"; cat $conf_dir/$CONF_NAME'"
}

#pull_conf () {
#  echo "Pulling $CONF_NAME..."
#  echo "Check and create folder $test_node_conf_dir in $script_dir folder"
#  [ ! -d $script_dir/$test_node_conf_dir ] && { mkdir -p $script_dir/$test_node_conf_dir; }
#
##  echo "ctrl_pattern: $ctrl_pattern"
#  echo "Try parse /etc/hosts to find ctrl node..."
##  ctrl_node=$(cat /etc/hosts | grep -m 1 -E ${ctrl_pattern} | awk '{print $1}')
#
#  nova_state_list=$(openstack compute service list)
#  ctrl_node=$(echo "$nova_state_list" | grep -m 1 -E "nova-scheduler" | awk '{print $6}')
#  echo "Pull consul conf from $ctrl_node:$conf_dir/region-config_${REGION}.json"
#  scp -o StrictHostKeyChecking=no $ctrl_node:$conf_dir/region-config_${REGION}.json $script_dir/$test_node_conf_dir
#}

pull_conf () {
  echo "Pulling $CONF_NAME..."
  [ ! -d $script_dir/$test_node_conf_dir ] && { mkdir -p $script_dir/$test_node_conf_dir; }


  echo "Сopying $service_name conf from ${NODES[0]}:$conf_dir/$CONF_NAME"
  ssh -o StrictHostKeyChecking=no $USER@${NODES[0]} "sudo cat $conf_dir/$CONF_NAME" > $script_dir/$test_node_conf_dir/${CONF_NAME}
#  scp -o StrictHostKeyChecking=no $USER@${NODES[0]}:$conf_dir/$CONF_NAME $script_dir/$test_node_conf_dir
  [ ! -f $script_dir/$test_node_conf_dir/${CONF_NAME}_backup ] && { cp $script_dir/$test_node_conf_dir/${CONF_NAME} $script_dir/$test_node_conf_dir/${CONF_NAME}_backup; }
  echo -e "
To edit the config:
  vi $script_dir/$test_node_conf_dir/$CONF_NAME
To apply the config:
  bash $script_dir/$script_name -push
"
}

push_conf () {
#  [ -z $CONF_NAME ] && { CONF_NAME=region-config_${REGION}.json; }
#  nova_state_list=$(openstack compute service list)
#  ctrl_nodes=$(echo "$nova_state_list" | grep -E "nova-scheduler" | awk '{print $6}')
#  ctrl_nodes=$(cat /etc/hosts | grep -E ${ctrl_pattern} | awk '{print $1}')
#  [ "$TS_DEBUG" = true ] && { for string in $ctrl_nodes; do debug_echo $string; done; }
#  if ! bash $utils_dir/$install_package_script host; then
#    exit 1
#  fi

#  "bind_address": "10.224.132.178",
  [ "$TS_DEBUG" = true ] && { for string in "${NODES[@]}"; do debug_echo $string; done; }

#  for node in $ctrl_nodes; do
  for node in "${NODES[@]}"; do
#    ip=$(host $node|grep -m 1 $node|awk '{print $4}')
    ip=$(ping $node -c 1|grep -m 1 -ohE "10\.224\.[0-9]{1,3}\.[0-9]{1,3}")
    check_ip=$(echo $ip|grep -m 1 -ohE "10\.224\.[0-9]{1,3}\.[0-9]{1,3}")
    if [ -n "$check_ip" ]; then
      [ "$TS_DEBUG" = true ] && { debug_echo $ip; echo "\"bind_address\": \"$ip\" on $CONF_NAME"; }
      sed -i --regexp-extended "s/\"bind_address\"(\s+|):\s+\"[0-9]+.[0-9]+.[0-9]+.[0-9]+\"\,/\"bind_address\": \"$ip\",/" \
        $script_dir/$test_node_conf_dir/$CONF_NAME
      sed -i --regexp-extended "s/\"bind_address\"(\s+|):\s+\".+\"\,/\"bind_address\": \"$ip\",/" \
        $script_dir/$test_node_conf_dir/$CONF_NAME
      sed -i --regexp-extended "s/consul_host(\s+|)=\s+[0-9]+.[0-9]+.[0-9]+.[0-9]+/consul_host = $ip/" \
        $script_dir/$test_node_conf_dir/$CONF_NAME
      echo "Push consul conf to $node:$conf_dir/$CONF_NAME"
#      scp -o StrictHostKeyChecking=no $script_dir/$test_node_conf_dir/$CONF_NAME $USER@$node:$conf_dir/$CONF_NAME
      scp -o StrictHostKeyChecking=no $script_dir/$test_node_conf_dir/$CONF_NAME $USER@$node:tmp/$CONF_NAME
      ssh -o StrictHostKeyChecking=no $USER@$node "sudo mv /tmp/$CONF_NAME $conf_dir/$CONF_NAME"
    else
      echo -e "${red}ip could not be define from hostname: $node - ERROR${normal}"
      exit 1
    fi
  done
}

get_nodes_list () {
  if [ -z "${NODES[*]}" ]; then
    nodes=$(bash $utils_dir/$get_nodes_list_script -nt $nodes_type)
  fi
#  node=$(cat /etc/hosts | grep -m 1 -E ${nodes_pattern} | awk '{print $2}')
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$node\": $node\n
  "
  for node in $nodes; do NODES+=("$node"); done
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$NODES\": ${NODES[*]}
  "
  echo -e "
  NODES: ${NODES[*]}
  "
  if [ -z "${NODES[*]}" ]; then
    echo -e "${red}Failed to determine node list - ERROR${normal}"
    exit 1
  fi
}

#change_alive_threshold () {
#  echo "Changing alive threshold..."
#  pull_conf
#  sed -i --regexp-extended "s/\"alive_compute_threshold\":\s+\"[0-9]+\"/\"alive_compute_threshold\": \"$1\"/" \
#   $script_dir/$test_node_conf_dir/region-config_${REGION}.json
#  push_conf
#  conf_changed="true"
#}

#change_dead_threshold () {
#  echo "Changing dead threshold..."
#  pull_conf
#  dead_threshold_string_exist=$(cat $script_dir/$test_node_conf_dir/region-config_${REGION}.json| grep 'dead_compute_threshold')
#
#  if [ -z "$dead_threshold_string_exist" ]; then
#    alive_threshold_string=$(cat $script_dir/$test_node_conf_dir/region-config_${REGION}.json| grep 'alive_compute_threshold')
#
#    sed -i --regexp-extended "s/$alive_threshold_string/${alive_threshold_string}\n   \"dead_compute_threshold\": \"$1\",/" \
#    $script_dir/$test_node_conf_dir/region-config_${REGION}.json
#  else
#    sed -i --regexp-extended "s/\"dead_compute_threshold\":\s+\"[0-9]+\",/\"dead_compute_threshold\": \"$1\",/" \
#      $script_dir/$test_node_conf_dir/region-config_${REGION}.json
#  fi
#  push_conf
##  cat_consul_conf
#  conf_changed="true"
#}

#change_ipmi_fencing () {
#  if [ "$1" = true ]; then
#    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"bmc\": false/\"bmc\": true/' $conf_dir/region-config_${REGION}.json"
#  elif [ "$1" = false ]; then
#    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"bmc\": true/\"bmc\": false/' $conf_dir/region-config_${REGION}.json"
#  else
#    echo "$1 - is not valid ipmi parameter"
#    return 1
#  fi
#  conf_changed="true"
#}

#change_nova_fencing () {
#  if [ "$1" = true ]; then
#    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"nova\": false/\"nova\": true/' $conf_dir/region-config_${REGION}.json"
#  elif [ "$1" = false ]; then
#    bash $script_dir/command_on_nodes.sh -nt ctrl -c "sed -i 's/\"nova\": true/\"nova\": false/' $conf_dir/region-config_${REGION}.json"
#  else
#    echo "$1 - is not valid nova parameter"
#    return 1
#  fi
#  conf_changed="true"
#}

check_bmc_suffix () {
  pull_conf
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]
  script_dir: $script_dir
  REGION: $REGION
  ${service_name}_conf_dir: $conf_dir
  "

  [ ! -f $script_dir/$test_node_conf_dir/$CONF_NAME ] && { echo "Config exists in: $script_dir/$test_node_conf_dir/$CONF_NAME"; pull_conf; }
  [ "$TS_DEBUG" = true ] && { echo -e "[DEBUG]\n"; ls -la $script_dir; }
  [ ! -f $script_dir/$test_node_conf_dir/$CONF_NAME ] && { echo "Config not found"; exit 1; }
  suffix_string_raw=$(cat $script_dir/$test_node_conf_dir/$CONF_NAME|grep 'suffix')
  if [ "$LEGACY_CONF" = true ]; then
    suffix_string_raw_2=${suffix_string_raw//\"/}
    echo "${suffix_string_raw_2%%,*}"|awk '{print $2}'
  else
    echo $suffix_string_raw|awk '{print $3}'
  fi
}

get_config_path () {
  echo $conf_dir/$CONF_NAME
}

get_nodes_list

if [ "$LEGACY_CONF" = true ]; then
  #check_and_source_openrc_file
  [[ -z "${OS_REGION_NAME}" ]] && { check_and_source_openrc_file; }
  [[ -z "${OS_REGION_NAME}" ]] && { echo "Region name not found"; exit 1; }
  conf_name="region-config_${OS_REGION_NAME}.json"
  CONF_NAME=$conf_name
fi

[ "$CHECK_SUFFIX" = true ] && { check_bmc_suffix; exit 0; }
[ "$GET_CONFIG_PATH" = true ] && { get_config_path; exit 0; }
[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }
[ "$PULL" = true ] && { pull_conf; exit 0; }
[ "$PUSH" = true ] && { push_conf; conf_changed=true; }
cat_conf
[ -n "$conf_changed" ] && { echo "Restart consul containers..."; bash $script_dir/command_on_nodes.sh $USER_STR -nt ctrl -c "docker restart consul"; }
#[ -n "$NOVA_FENCING" ] && change_nova_fencing $NOVA_FENCING
#[ -n "$IPMI_FENCING" ] && change_ipmi_fencing $IPMI_FENCING
#[ -n "$DEAD_THRSHOLD" ] && change_dead_threshold $DEAD_THRSHOLD
#[ -n "$ALIVE_THRSHOLD" ] && change_alive_threshold $ALIVE_THRSHOLD
