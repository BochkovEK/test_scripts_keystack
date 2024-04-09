# The script change and check drs config
# Start scrip to check conf: bash edit_drs_config.sh check

ctrl_pattern="\-ctrl\-..$"
service_name=adminui-backend
conf_name=adminui-backend-regions.conf
test_node_conf_dir=kolla/$service_name
conf_dir=/etc/kolla/$service_name

script_dir=$(dirname $0)
conf_changed=""

#[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $ADD_DEBUG ]] && ADD_DEBUG="false"
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

        -foo,      -bar           <baz>
        -gt        -gitlab_token  <token> add token to gitlab_password = string if it empty
        -v,        -debug         without value, set DEBUG=\"true\"

        Start the scrip with parameter check to check conf: bash edit_drs_config.sh check
        "
          exit 0
          break ;;
        -v|-debug) DEBUG="true"
	        echo "Found the -debug, parameter set $DEBUG"
          ;;
        -gt|-gitlab_token) GITLAB_TOKEN=$2
	        echo "Found the-gitlab_token, parameter set $GITLAB_TOKEN"
          ;;
        --) shift
          break ;;
        *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
        esac
        shift
done

cat_conf () {
  echo "Cat all $service_name configs..."
  bash $script_dir/command_on_nodes.sh -nt ctrl -c "echo \"cat $conf_dir/$conf_name\"; cat $conf_dir/$conf_name"
}

pull_conf () {
  [ ! -d $test_node_conf_dir ] && { mkdir -p $test_node_conf_dir; }
  ctrl_node=$(cat /etc/hosts | grep -m 1 -E ${ctrl_pattern} | awk '{print $2}')
  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: \"\$ctrl_node\": $ctrl_node\n
  "

  echo "Сopying $service_name conf from $ctrl_node:$conf_dir/$conf_name"
  scp -o StrictHostKeyChecking=no $ctrl_node:$conf_dir/$conf_name $test_node_conf_dir
}

push_conf () {
  ctrl_nodes=$(cat /etc/hosts | grep -E ${ctrl_pattern} | awk '{print $2}')

  for node in $ctrl_nodes; do
    if [ "$DEBUG" = true ]; then
      echo -e "
  [DEBUG]: \"\$ctrl_nodes\": $string\n
  "
    fi
    echo "Сopying $service_name conf to $node:$conf_dir/$conf_name"
    scp -o StrictHostKeyChecking=no $test_node_conf_dir/$conf_name $node:$conf_dir/$conf_name
  done
}

#change_foo_param () {
#  <logics>
#  conf_changed=true
#}

change_gitlab_password_param () {
  pull_conf
  sed -i -E "s,gitlab_password =$,gitlab_password = $GITLAB_TOKEN,g" $script_dir/$test_node_conf_dir/$conf_name
  push_conf
  conf_changed="true"
}


[ "$ONLY_CONF_CHECK" = true ] && { cat_conf; exit 0; }
[ "$ADD_DEBUG" = true ] && { change_add_debug_param; }
#[ -n "$CHANGE_FOO_PARAM" ] && change_foo_param $foo_param_value
[ -n "$conf_changed" ] && { container_service_name=$(echo "$service_name" | sed 's/-/_/g' ); cat_conf; echo "Restart $container_service_name containers..."; bash command_on_nodes.sh -nt ctrl -c "docker restart $container_service_name"; exit 0; }
cat_conf

