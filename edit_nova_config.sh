# The script change and check drs config
# Start scrip to check conf: bash edit_drs_config.sh check

#nodes_pattern="\-comp\-..$"
nodes_type="comp"
service_name=nova-compute
test_node_conf_dir=kolla/$service_name
conf_dir=/etc/kolla/$service_name
conf_name=nova.conf

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

script_dir=$(dirname $0)
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
conf_changed=""

#[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $ADD_DEBUG ]] && ADD_DEBUG="false"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK="true"
[[ -z $ADD_PROM_ALERT ]] && ADD_PROM_ALERT=""
[[ -z $PROMETHEUS_PASS ]] && PROMETHEUS_PASS=""
[[ -z $PUSH ]] && PUSH="false"
[[ -z $PULL ]] && PULL="false"
[[ -z $CONF_NAME ]] && CONF_NAME=$conf_name
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

        -foo,       -bar                <baz>
        -add_debug                      without value, add DEBUG level to log by drs config
        -v,         -debug              without value, set DEBUG=\"true\"
        -pull                           without value, pull config from $conf_dir/$conf_name
                                        on $nodes_pattern node to
                                        $script_dir/$test_node_conf_dir
        -push                           without value, push config from $script_dir/$test_node_conf_dir
                                        on $nodes_pattern node to $conf_dir/$conf_name
        -check                          only check option (without parameter)

        Start the scrip with parameter check to check conf: bash edit_drs_config.sh check
        "
          exit 0
          break ;;
        -v|-debug) TS_DEBUG="true"
	        echo "Found the -debug, parameter set $TS_DEBUG"
          ;;
        -add_debug) ADD_DEBUG="true"
	        echo "Found the --add_debug, parameter set $ADD_DEBUG"
          ;;
#        -pa|-prometheus_alerting) PROMETHEUS_PASS="$2"; ADD_PROM_ALERT="true"
#	        echo "Found the -prometheus_alerting, \$PROMETHEUS_PASS: $PROMETHEUS_PASS"
#          shift;;
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

cat_conf () {
  echo "Cat all $service_name configs..."
  bash $script_dir/command_on_nodes.sh -nt $nodes_type -c "echo \"cat $conf_dir/$CONF_NAME\"; cat $conf_dir/$CONF_NAME"
}

pull_conf () {
  echo "Pulling $CONF_NAME..."
  [ ! -d $script_dir/$test_node_conf_dir ] && { mkdir -p $script_dir/$test_node_conf_dir; }
  nodes=$(bash $utils_dir/$get_nodes_list_script)
#  node=$(cat /etc/hosts | grep -m 1 -E ${nodes_pattern} | awk '{print $2}')
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$node\": $node\n
  "
  for node in $nodes; do NODES+=("$node"); done
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$NODES\": ${NODES[*]}
  "
  echo "Сopying $service_name conf from ${NODES[0]}:$conf_dir/$CONF_NAME"
  scp -o StrictHostKeyChecking=no ${NODES[0]}:$conf_dir/$CONF_NAME $script_dir/$test_node_conf_dir
}

push_conf () {
  echo "Pushing $CONF_NAME..."
  nodes=$(cat /etc/hosts | grep -E ${nodes_pattern} | awk '{print $1}')

  for node in $nodes; do
    if [ "$TS_DEBUG" = true ]; then
      echo -e "
  [DEBUG]: \"\$node\": $node\n
  "
    fi
    #change api_host = 10.224.132.178
    echo "sed api_host = $node on $CONF_NAME"
    sed -i --regexp-extended "s/api_host\s+=\s+[0-9]+.[0-9]+.[0-9]+.[0-9]+/api_host = $node/" \
      $script_dir/$test_node_conf_dir/$CONF_NAME
#    sed -i --regexp-extended  "s/https\:\/\/[0-9]+.[0-9]+.[0-9]+.[0-9]+/https\:\/\/$node/" \
#      $script_dir/$test_node_conf_dir/$CONF_NAME
#    sed -i --regexp-extended  "s/\@[0-9]+.[0-9]+.[0-9]+.[0-9]+/@$node/" \
#      $script_dir/$test_node_conf_dir/$CONF_NAME
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

#change_add_prometheus_alerting () {
#  echo "Add prometheus alerting to drs.ini..."
#  if [ -z "${PROMETHEUS_PASS}" ]; then
#    echo "${red}\$PROMETHEUS_PASS not set. Prometheus alerting not set in $conf_name${reset}"
#    ONLY_CONF_CHECK="false"
#  else
#    pull_conf
#    prom_pass_exists=$(cat $script_dir/$test_node_conf_dir/$CONF_NAME|grep prometheus_alert_manager_password)
#    if [ -z "$prom_pass_exists" ]; then
#  #    sed -i "s/\[prometheus\]/\[prometheus\]\nenable_prometheus_alert_manager_auth = true\nprometheus_alert_manager_user = admin\nprometheus_alert_manager_password = $PROMETHEUS_PASS/" $script_dir/$test_node_conf_dir/$conf_name
#    sed -i "s/\[alerting\]/\[alerting\]\nenable_prometheus_alert_manager_auth = true\nprometheus_alert_manager_user = admin\nprometheus_alert_manager_password = $PROMETHEUS_PASS/" $script_dir/$test_node_conf_dir/$conf_name
#    sed -i "s/enable_alerting = false/enable_alerting = true/" $script_dir/$test_node_conf_dir/$conf_name
#    fi
#    push_conf
#    conf_changed="true"
#  fi
#}


[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }
[ "$PUSH" = true ] && { push_conf; conf_changed=true; }
[ "$PULL" = true ] && { pull_conf; exit 0; }
[ "$ADD_DEBUG" = true ] && { change_add_debug_param; }
#[ -n "$ADD_PROM_ALERT" ] && { change_add_prometheus_alerting; }
#[ -n "$CHANGE_FOO_PARAM" ] && change_foo_param $foo_param_value
[ -n "$conf_changed" ] && { cat_conf; echo "Restart $service_name containers..."; bash $script_dir/command_on_nodes.sh -nt ctrl -c "docker restart $service_name"; exit 0; }
#[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }
#cat_conf

