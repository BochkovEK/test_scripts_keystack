# The scrip disable autorestart nova_compute and consul docker containers

comp_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"
nodes_to_find="$comp_pattern"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ -z $SERVICE_NAME ]] && SERVICE_NAME=""
[[ -z $NODES ]] && NODES=()

while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
  The scrip disable autorestart nova_compute and consul docker containers
"
      exit 0
      break ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
      esac
      shift
done

[[ -z ${NODES[0]} ]] && { srv=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}'); for i in $srv; do NODES+=("$i"); done; }

echo "Nodes for disable kolla container service:"
echo "${NODES[*]}"

for host in "${NODES[@]}"; do
  echo "Edit config kolla service on ${host}"
  if ping -c 2 $host &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $host - ok!${normal}"
    ssh -o StrictHostKeyChecking=no $host sed -i 's/Restart=always/Restart=no/' /etc/systemd/system/kolla-consul-container.service
    ssh -o StrictHostKeyChecking=no $host cat /etc/systemd/system/kolla-consul-container.service
    ssh -o StrictHostKeyChecking=no $host sed -i 's/Restart=always/Restart=no/' /etc/systemd/system/kolla-nova_compute-container.service
    ssh -o StrictHostKeyChecking=no $host cat /etc/systemd/system/kolla-nova_compute-container.service
    echo "Daemon reloading on ${host}..."
    ssh -o StrictHostKeyChecking=no $host systemctl daemon-reload
  fi
done
