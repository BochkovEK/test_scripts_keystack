# The script change and check drs config
# Start scrip to check conf: bash edit_drs_config.sh check

ctrl_pattern="\-ctrl\-..$"
service_name=drs
test_node_conf_dir=kolla/$service_name
conf_dir=/etc/kolla/drs
#conf_name=drs.ini

script_dir=$(dirname $0)
conf_changed=""

#[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $ADD_DEBUG ]] && ADD_DEBUG="false"
[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK="false"
[[ -z $PROMETHEUS_PASS ]] && PROMETHEUS_PASS=""
[[ -z $PUSH ]] && PUSH="false"
[[ -z $CONF_NAME ]] && CONF_NAME="drs.ini"
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

        -foo,       -bar                  <baz>
        -add_debug                        without value, add DEBUG level to log by drs config
        -v,         -debug                without value, set DEBUG=\"true\"
        -pa,        -prometheus_alerting  <prometheus_password>
        -p,         -push                 without value, push region-config_<region_name>.json from
                                          $HOME/test_scripts_keystack/$test_node_conf_dir/$CONF_NAME to
                                          $conf_dir/$CONF_NAME on ctrl nodes

        Start the scrip with parameter check to check conf: bash edit_drs_config.sh check
        "
          exit 0
          break ;;
        -v|-debug) DEBUG="true"
	        echo "Found the -debug, parameter set $DEBUG"
          ;;
        -add_debug) ADD_DEBUG="true"
	        echo "Found the -debug, parameter set $ADD_DEBUG"
          ;;
        -pa|-prometheus_alerting) PROMETHEUS_PASS="$2"
	        echo "Found the -prometheus_alerting, parameter set $PROMETHEUS_PASS"
          shift;;
        -p|-push) PUSH="true"
	        echo "Found the -push, parameter set $PUSH"
          ;;
        --) shift
          break ;;
        *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
        esac
        shift
done

cat_conf () {
  echo "Cat all $service_name configs..."
  bash $script_dir/command_on_nodes.sh -nt ctrl -c "echo \"cat $conf_dir/$CONF_NAME\"; cat $conf_dir/$CONF_NAME"
}

pull_conf () {
  echo "Pulling drs.ini..."
  [ ! -d $script_dir/$test_node_conf_dir ] && { mkdir -p $script_dir/$test_node_conf_dir; }
  ctrl_node=$(cat /etc/hosts | grep -m 1 -E ${ctrl_pattern} | awk '{print $2}')
  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$ctrl_node\": $ctrl_node\n
  "

  echo "Сopying $service_name conf from $ctrl_node:$conf_dir/$CONF_NAME"
  scp -o StrictHostKeyChecking=no $ctrl_node:$conf_dir/$CONF_NAME $script_dir/$test_node_conf_dir
}

push_conf () {
  echo "Pushing drs.ini..."
  ctrl_nodes=$(cat /etc/hosts | grep -E ${ctrl_pattern} | awk '{print $2}')

  for node in $ctrl_nodes; do
    if [ "$DEBUG" = true ]; then
      echo -e "
  [DEBUG]: \"\$ctrl_nodes\": $string\n
  "
    fi
    #change api_host = 10.224.132.178
    echo "sed api_host = $node on $CONF_NAME"
    sed -i --regexp-extended "s/api_host\s+=\s+[0-9]+.[0-9]+.[0-9]+.[0-9]+/api_host = $node/" \
      $script_dir/$test_node_conf_dir/$CONF_NAME
    echo "Сopying $service_name conf to $node:$conf_dir/$CONF_NAME"
    scp -o StrictHostKeyChecking=no $script_dir/$test_node_conf_dir/$CONF_NAME $node:$conf_dir/$CONF_NAME
  done
}

#change_foo_param () {
#  <logics>
#  conf_changed=true
#}

change_add_debug_param () {
  echo "Add debug to drs.ini..."

  pull_conf
  sed -i 's/\[DEFAULT\]/\[DEFAULT\]\ndebug = true/' $script_dir/$test_node_conf_dir/$CONF_NAME
  push_conf
  conf_changed="true"
}

change_add_prometheus_alerting () {
  echo "Add prometheus alerting to drs.ini..."
  pull_conf
  prom_pass_exists=$(cat $script_dir/$test_node_conf_dir/$CONF_NAME|grep prometheus_alert_manager_password)
  if [ -z "$prom_pass_exists" ]; then
#    sed -i "s/\[prometheus\]/\[prometheus\]\nenable_prometheus_alert_manager_auth = true\nprometheus_alert_manager_user = admin\nprometheus_alert_manager_password = $PROMETHEUS_PASS/" $script_dir/$test_node_conf_dir/$conf_name
  sed -i "s/\[alerting\]/\[alerting\]\nenable_prometheus_alert_manager_auth = true\nprometheus_alert_manager_user = admin\nprometheus_alert_manager_password = $PROMETHEUS_PASS/" $script_dir/$test_node_conf_dir/$conf_name
  sed -i "s/enable_alerting = false/enable_alerting = true/" $script_dir/$test_node_conf_dir/$conf_name
  fi
  push_conf
  conf_changed="true"
}


[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }
[ "$PUSH" = true ] && { push_conf; conf_changed=true; }
[ "$ADD_DEBUG" = true ] && { change_add_debug_param; }
[ -n "$PROMETHEUS_PASS" ] && { change_add_prometheus_alerting; }
#[ -n "$CHANGE_FOO_PARAM" ] && change_foo_param $foo_param_value
[ -n "$conf_changed" ] && { cat_conf; echo "Restart $service_name containers..."; bash $script_dir/command_on_nodes.sh -nt ctrl -c "docker restart $service_name"; exit 0; }
cat_conf

