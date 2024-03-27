# The script change and check drs config
# ???openrc file required in ~/
# Start scrip to check conf: bash edit_drs_config.sh check

ctrl_pattern="\-ctrl\-..$"
service_name=drs
test_node_conf_dir=kolla/$service_name
conf_dir=/etc/kolla/drs
conf_name=drs.ini

script_dir=$(dirname $0)

#[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK="false"
#[[ -z $FOO_PARAM ]] && FOO_PARAM=""


# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [ "$1" = check ] && { ONLY_CONF_CHECK=true; echo "Only conf check parameter found"; }
}

count=1
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The script change and check drs config

        -foo,   -bar          <baz>
        -v,     -debug        without value, set DEBUG=\"true\"

        Start the scrip with parameter check to check conf: bash edit_drs_config.sh check
        "
          exit 0
          break ;;
        -v|-debug) DEBUG="true"
	        echo "Found the -debug, parameter set $DEBUG"
          ;;
        --) shift
          break ;;
        *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
        esac
        shift
done


#source $OPENRC_PATH
#REGION=$OS_REGION_NAME
#[[ -z "${REGION}" ]] && { echo "Region name not found"; exit 1; }

debug_echo () {
  echo "[DEBUG] \$1: $1"
}

#Check_openrc_file () {
#    echo "Check openrc file here: $OPENRC_PATH"
#    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
#    #echo $OPENRC_PATH
#    #echo $check_openrc_file
#    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
#}

cat_conf () {
  echo "Cat all $service_name configs..."
  bash $script_dir/command_on_nodes.sh -nt ctrl -c "echo \"cat $conf_dir/$conf_name\"; cat $conf_dir/$conf_name"
}

pull_conf () {
  [ ! -d $test_node_conf_dir ] && { mkdir -p $test_node_conf_dir; }
  ctrl_node=$(cat /etc/hosts | grep -m 1 -E ${ctrl_pattern} | awk '{print $2}')
  [ "$DEBUG" = true ] && debug_echo $ctrl_node

  echo "Сopying $service_name conf from $ctrl_node:$conf_dir/$conf_name"
  scp -o StrictHostKeyChecking=no $$ctrl_node:$conf_dir/$conf_name $test_node_conf_dir
}

push_conf () {
  ctrl_nodes=$(cat /etc/hosts | grep -E ${ctrl_pattern} | awk '{print $2}')
  [ "$DEBUG" = true ] && { for string in $ctrl_nodes; do debug_echo $string; done; }
  for node in $ctrl_nodes; do
    echo "Сopying $service_name conf to $node:$conf_dir/$conf_name"
    scp -o StrictHostKeyChecking=no $test_node_conf_dir/$conf_name $node:$conf_dir/$conf_name
  done
}

#change_foo_param () {
#  <logics>
#  conf_changed=true
#}


#[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }

#[ -n "$CHANGE_FOO_PARAM" ] && change_foo_param $foo_param_value
[ -n "$conf_changed" ] && { cat_conf; echo "Restart $service_name containers..."; bash command_on_nodes.sh -nt ctrl -c "docker restart $service_name"; exit 0; }
cat_conf

