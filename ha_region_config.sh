# The script change alive_threshold in consul region config
# openrc file required in ~/
# Start scrip: bash ha_region_config.sh -a 2

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $ALIVE_THRSHOLD ]] && ALIVE_THRSHOLD=""
[[ -z $DEAD_THRSHOLD ]] && DEAD_THRSHOLD=""
[[ -z $IPMI_FENCING ]] && IPMI_FENCING=""

#[[ -z "${1}" ]] && { echo "Alive threshold value required as parameter script"; exit 1; }

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The script change consul region config
        openrc file required in ~/

        -a,   -alive_threshold          <alive_threshold>
        -d,   -dead_compute_threshold   <dead_compute_threshold>
        -i,   -ipmi_fencing             <true\false>
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
        --) shift
          break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

# Define parameters
count=1
for param in "$@"
do
        echo "Parameter #$count: $param"
        count=$(( $count + 1 ))
done

source $OPENRC_PATH
REGION=$OS_REGION_NAME
[[ -z "${REGION}" ]] && { echo "Region name not found"; exit 1; }

change_alive_threshold () {
  bash command_on_nodes.sh -nt ctrl -c "sed -i --regexp-extended 's/"alive_compute_threshold":\s+"[0-9]+"/"alive_compute_threshold": "$1"/' /etc/kolla/consul/region-config_${REGION}.json"
  conf_id_changed="true"
}

change_dead_threshold () {
#  alive_threshold_string=$(cat /etc/kolla/consul/region-config_${REGION}.json| grep 'alive_compute_threshold')
bash command_on_nodes.sh -nt ctrl -c 'echo $REGION; foo=bar; echo $foo'
#  bash command_on_nodes.sh -nt ctrl -c "echo $REGION; alive_threshold_string=$(cat /etc/kolla/consul/region-config_${REGION}.json| grep 'alive_compute_threshold'); echo $alive_threshold_string"
#  alive_threshold_string=$(cat /etc/kolla/consul/region-config_${REGION}.json| grep 'alive_compute_threshold');
#  sed -i --regexp-extended "s/$alive_threshold_string/$alive_threshold_string\n   \"dead_compute_threshold\": \"$1\",/" /etc/kolla/consul/region-config_${REGION}.json; }"
#  conf_id_changed="true"
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

cat_consul_conf () {
  bash command_on_nodes.sh -nt ctrl -c "cat /etc/kolla/consul/region-config_${REGION}.json"
}

[ -n "$ALIVE_THRSHOLD" ] && change_alive_threshold $ALIVE_THRSHOLD
[ -n "$DEAD_THRSHOLD" ] && change_dead_threshold $DEAD_THRSHOLD
[ -n "$IPMI_FENCING" ] && change_ipmi_fencing $IPMI_FENCING
[ -n "$conf_id_changed" ] && { echo "Restart consul containers..."; bash command_on_nodes.sh -nt ctrl -c "docker restart consul"; cat_consul_conf; }
#cat_consul_conf