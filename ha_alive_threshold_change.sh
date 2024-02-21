# The script change alive_threshold in consul region config
# openrc file required in ~/
# Start scrip: bash change_ha_alive_threshold.sh <alive_threshold_value>

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"

[[ -z "${1}" ]] && { echo "Alive threshold value required as parameter script"; exit 1; }

source $OPENRC_PATH

REGION=$OS_REGION_NAME

bash command_on_nodes.sh -nt ctrl -c "sed -i 's/\"alive_compute_threshold\": \"1\"/\"alive_compute_threshold\": \"$1\"/' /etc/kolla/consul/region-config_${REGION}.json"
bash command_on_nodes.sh -nt ctrl -c "docker restart consul"