# The scrip disable autorestart nova_compute and consul docker containers

comp_pattern="\-comp\-..($|\s)"
ctrl_pattern="\-ctrl\-..($|\s)"
net_pattern="\-net\-..($|\s)"
nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ -z $SERVICE_NAME ]] && SERVICE_NAME="consul nova_compute"
[[ -z $NODES ]] && NODES=()

while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
  The scrip disable autorestart nova_compute and consul docker containers or specify service
  -s,           -service          <kolla service name>
"
      exit 0
      break ;;
    -s|-service) SERVICE_NAME="$2"
      echo "Found the -service option, with parameter value $SERVICE_NAME"
      shift ;;
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
    for SERVICE in $SERVICE_NAME; do
    #if [ -z $SERVICE_NAME ]; then
      echo "Try sed Restart for $SERVICE"
      ssh -o StrictHostKeyChecking=no $host "sed -i
        's/Restart=always/Restart=no/';
        's/\-t 60//'
        /etc/systemd/system/kolla-$SERVICE-container.service"
#      ssh -o StrictHostKeyChecking=no $host cat /etc/systemd/system/kolla-consul-container.service
#      ssh -o StrictHostKeyChecking=no $host sed -i 's/Restart=always/Restart=no/' /etc/systemd/system/kolla-nova_compute-container.service
#      ssh -o StrictHostKeyChecking=no $host cat /etc/systemd/system/kolla-nova_compute-container.service
#    else
#      echo "Try sed Restart=always for $SERVICE_NAME"
#      ssh -o StrictHostKeyChecking=no $host sed -i 's/Restart=always/Restart=no/' /etc/systemd/system/kolla-$SERVICE_NAME-container.service
#      ssh -o StrictHostKeyChecking=no $host cat /etc/systemd/system/kolla-$SERVICE_NAME-container.service
#      echo "Daemon reloading on ${host}..."
#      ssh -o StrictHostKeyChecking=no $host systemctl daemon-reload
#    fi
    done
  fi
done
