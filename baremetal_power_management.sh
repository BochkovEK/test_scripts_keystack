# The power management script
# Example start:
#  bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 check
#  bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 on


#utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
edit_ha_config_script="edit_ha_config.sh"
default_ssh_user="root"
default_ssh_port=22

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
#violet=$(tput setaf 5)
yellow=$(tput setaf 3)
normal=$(tput sgr0)

required_modules=(
            #foo
            "sushy"
#            "sys"
)

script_dir=$(dirname $0)
utils_dir="$script_dir/utils"

[[ -z $HOST_NAME ]] && HOST_NAME=""
[[ -z $IPMI_IP ]] && IPMI_IP=""
[[ -z $POWER_STATE ]] && POWER_STATE="check"
[[ -z $IPMI_USER ]] && IPMI_USER=""
[[ -z $IPMI_PASSWORD ]] && IPMI_PASSWORD=""
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $EDIT_HA_REGION_CONFIG ]] && EDIT_HA_REGION_CONFIG=$edit_ha_config_script
[[ -z $BMC_SUFFIX ]] && BMC_SUFFIX=""
#[[ -z $POSTFIX ]] && POSTFIX="rmi"
[[ -z $SSH_TIMEOUT ]] && SSH_TIMEOUT=300
[[ -z $SSH_INTERVAL ]] && SSH_INTERVAL=3
[[ -z $SSH_PORT ]] && SSH_PORT=$default_ssh_port
#=============================================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { HOST_NAME=$1; echo "Host name parameter found with value: \"$HOST_NAME\""; }
  [ "$count" = 2 ] && [[ -n $1 ]] && { POWER_STATE=$1; echo "Power state parameter found with value: \"$POWER_STATE\""; }
  [ "$count" = 3 ] && [[ -n $1 ]] && { IPMI_USER=$1; echo "User name parameter found with value: \"$IPMI_USER\""; }
  [ "$count" = 4 ] && [[ -n $1 ]] && { IPMI_PASSWORD=$1; echo "Password parameter found with value: \"$IPMI_PASSWORD\""; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
  --help) echo -E "
    The power management script
      -ip <ipmi_ip>                           IPMI IP
      -hv, -host_name <host_name>             Host name for power management (ipmi)
      -p, -power_state <power_state>          Check, on, off, restart, shutdown
      -v, -debug                              Enabled debug output (without parameter)
      -ipmi_pswd <password_for_idrac>         idrac password
      -ipmi_user <user_name_for_idrac>           idrac username
      -b, -bmc_suffix <bmc_suffix_for_impi>   Example: cdm-bl-pca04-rmi (bmc_suffix = rmi)
      -u, ssh_user  <ssh_user>                SSH user for get ipmi suffix and check connection after startup node
      -t, -ssh_timeout <ssh_timeout>          Timeout for ssh connection to node (sec)
      -i, -ssh_interval <ssh_interval>        Interval for check ssh connection to node (sec)

      Example to start script:
           bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 check
           bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 on
"
#-pf, -postfix          <postfix>       Postfix for host name power management (ipmi; example: rmi)

    exit 0
    break ;;
  -ip) IPMI_IP="$2"
    echo "Found the -ip <ipmi_ip> option, with parameter value $IPMI_IP"
    shift ;;
  -hv|-host_name) HOST_NAME="$2"
    echo "Found the -host_name <host_name> option, with parameter value $HOST_NAME"
    shift ;;
  -ipmi_user) IPMI_USER="$2"
    echo "Found the -ipmi_user option, with parameter value $IPMI_USER"
    shift ;;
  -ipmi_pswd) IPMI_PASSWORD="$2"
    echo "Found the -ipmi_pswd option, with parameter value $IPMI_PASSWORD"
    shift ;;
  -u|ssh_user) SSH_USER="$2"
    echo "Found the -ssh_user option, with parameter value $SSH_USER"
    shift ;;
  -v|-debug) TS_DEBUG="true"
	  echo "Found the -debug, with parameter value $TS_DEBUG"
    ;;
  -p|-power_state) POWER_STATE="$2"
	  echo "Found the -power_state, with parameter value $POWER_STATE"
    shift ;;
  -b|-bmc_suffix) BMC_SUFFIX="$2"
    echo "Found the -bmc_suffix, with parameter value $BMC_SUFFIX"
    shift ;;
  -t|ssh_timeout) SSH_TIMEOUT="$2"
    echo "Found the -ssh_timeout, with parameter value $SSH_TIMEOUT"
    shift ;;
  -i|ssh_interval) SSH_INTERVAL="$2"
    echo "Found the -ssh_interval, with parameter value $SSH_INTERVAL"
    shift ;;
  --) shift
      break ;;
  *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
   esac
   shift
done

## Function to get nodes list using external script
#get_nodes_list() {
##    [ "$TS_DEBUG" = true ] && echo -e "
##    [DEBUG]:
##        Count parameters: $#
##        Parameters: $*
##    "
#
#    local nodes_result=""
#
#    nodes_result=$(bash "$script_dir/$utils_dir/$get_nodes_list_script" "$@")
#
##    [ "$TS_DEBUG" = true ] && echo -e "
##    [DEBUG] nodes_result: $nodes_result"
#
#    if [ -z "$nodes_result" ]; then
#        echo -e "${red}Failed to determine node list - ERROR${normal}"
#        exit 1
#    elif echo "$nodes_result" | grep -q "ERROR"; then
#        echo -e "${yellow}Node names could not be determined.${normal}"
#        echo -e "${yellow}Try: bash $script_dir/$utils_dir/$get_nodes_list_script -nt all${normal}"
#        echo -e "${red}Node names could not be determined - ERROR!${normal}"
#        exit 1
#    else
#        echo "$nodes_result"
#    fi
#}

# Function to get nodes list using external script
get_nodes_list() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
      nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$*\")"

#    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

    if ! nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@" 2>&1); then
#        exit_code=$?
        echo -e "${red}ERROR: Node list script failed${normal}" >&2
        echo -e "${red}Output: $nodes_result${normal}" >&2
        return 1
    fi

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result: $nodes_result
    "

    # Check for errors in node list
    if [ -z "$nodes_result" ]; then
        echo -e "${red}Failed to determine node list - ERROR${normal}"
        exit 1
    elif echo "$nodes_result" | grep -q "ERROR"; then
        echo -e "${yellow}Node names could not be determined.${normal}"
        echo -e "${yellow}Try: bash $utils_dir/$get_nodes_list_script -nt all${normal}"
        echo -e "${red}Node names could not be determined - ERROR!${normal}"
        exit 1
    else
        echo "$nodes_result"
    fi
}

check_connection_to_ipmi () {
    echo "Check connection to BMC IP: $IPMI_IP"

    if [ -z "$IPMI_IP" ]; then
        printf "%40s\n" "${red}BMC IP is empty - error!${normal}"
        exit 1
    fi

    if ! [[ $IPMI_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf "%40s\n" "${red}Invalid IPMI IP format: $IPMI_IP${normal}"
        exit 1
    fi

    if ping -c 2 $IPMI_IP &> /dev/null; then
        printf "%40s\n" "${green}There is a connection with BMC ($IPMI_IP) - success${normal}"
    else
        printf "%40s\n" "${red}No connection with BMC ($IPMI_IP) - error!${normal}"
        exit 1
    fi
}
check_module_exist () {
  for module in "${required_modules[@]}"; do
    module_exists=$(pip list| grep $module)

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]: module: $module
    [DEBUG]: module_exists: $module_exists
  "

    [ -z "$module_exists" ] && { echo "Install $module"; pip install $module; }
  done
}

python_script_execute () {
  echo "Send command $1 to $BMC_HOST_NAME"
  python3 $script_dir/redfish_manager.py $BMC_HOST_NAME $1 $IPMI_USER $IPMI_PASSWORD
}

wait_for_ssh_connection () {
  echo "Waiting for SSH availability on $HOST_NAME..."

  local hv_pair

  hv_pair=$(bash "$utils_dir/$get_nodes_list_script" -nn $HOST_NAME)
  if [ -n "$hv_pair" ]; then
      local node_name="${hv_pair%%:*}"
      local node_ip="${hv_pair#*:}"
  else
      echo -e "${yellow}Failed to define any ctrl node${normal}"
      return 1
  fi

  # SSH availability check loop
  for (( i=0; i<$SSH_TIMEOUT; i+=$SSH_INTERVAL )); do
    # Check port availability (using nc or ssh)
    if nc -z -w 2 "$node_ip" "$SSH_PORT" 2>/dev/null; then
      echo "SSH is available!"
      break
    fi

    echo "Attempt $((i/SSH_INTERVAL + 1)): SSH not yet available. Waiting $SSH_INTERVAL sec..."
    sleep $SSH_INTERVAL
  done

  # Exit if timeout reached
  if (( i >= SSH_TIMEOUT )); then
    echo "Error: SSH on $HOST_NAME didn't become available within $SSH_TIMEOUT seconds!" >&2
    exit 1
  fi

  ### Proceed with SSH commands if available ###
  echo "Executing commands via SSH..."
  ssh $SSH_USER@$node_ip "ls -la"
}

start_command () {
  actual_power_state=$(python_script_execute check| tail -n1)
  echo "Actual ipmi satus: $actual_power_state"
  if [ "$actual_power_state" = "PowerState.OFF" ]; then
#          Check_openrc_file
#          source $OPENRC_PATH
    # The next two lines are commented out because the functionality of the consul has been changed 2024.2-rc-1
#          echo "Trying set --disable-reason \"test disable\" to $HOST_NAME"
#          openstack compute service set --disable --disable-reason "test disable" $HOST_NAME nova-compute
    echo "Trying set power state \"on\" on $HOST_NAME"
    python_script_execute on
#    sent_launch_command=$(python_script_execute on)
#    [ "$sent_launch_command" = "None" ] && { echo "The host: $HOST_NAME startup command has been successfully sent"; }
    wait_for_ssh_connection
  fi
}

start_python_power_management_script () {
    echo "Check power state parameter: $POWER_STATE..."
    if [ -z "$IPMI_IP" ]; then
      # Determining the ipmi suffix from VMHA configs is not required as the information is taken from the $STAND_NAME/hosts file

      [ "$TS_DEBUG" = true ] && echo -e "
        [DEBUG] Looking for BMC: $HOST_NAME
        [DEBUG] Command: bmc_info=\$(bash \"$utils_dir/$get_nodes_list_script\" -nt rmi \"$bmc_suffix\")
      "

      bmc_list=$(bash "$utils_dir/$get_nodes_list_script" -nt rmi)

      [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] bmc_list from get_nodes_list: $bmc_list"

      for entry in $bmc_list; do
          if [[ "$entry" == "$HOST_NAME:"* ]]; then
              bmc_info="$entry"
              break
          fi
      done

      # Извлекаем IP
      IPMI_IP="${bmc_info#*:}"  # Все после двоеточия

      # Очищаем от возможных пробелов
      IPMI_IP=$(echo "$IPMI_IP" | tr -d '[:space:]')

      echo "IPMI_IP: $IPMI_IP"
    fi

    # Проверяем, что IPMI_IP установлен
    if [ -z "$IPMI_IP" ]; then
        echo -e "${red}ERROR: IPMI_IP is empty!${normal}"
        exit 1
    fi

    check_connection_to_ipmi
    case $POWER_STATE in
      check)
        python_script_execute check
        ;;
      on|start)
        start_command
        ;;
      off)
        actual_power_state=$(python_script_execute check| tail -n1)
        echo "Actual ipmi satus: $actual_power_state"
        if [ "$actual_power_state" = "PowerState.ON" ]; then
          python_script_execute off
        fi
        ;;
      restart)
        python_script_execute restart
        ;;
      shutdown)
        actual_power_state=$(python_script_execute check| tail -n1)
        echo "Actual ipmi satus: $actual_power_state"
        if [ "$actual_power_state" = "PowerState.ON" ]; then
          python_script_execute shutdown
        fi
        ;;
      *)
        echo "Unknown power state parameter: $POWER_STATE"
        return 1
        ;;
    esac
}

#start_python_power_management_script () {
#    echo "Check power state parameter: $POWER_STATE..."
#    if [ -n "$IPMI_IP" ]; then
#      BMC_HOST_NAME=$IPMI_IP
#    else
#      if [ -z $BMC_SUFFIX ]; then
#        echo "Check bmc suffix by script $EDIT_HA_REGION_CONFIG..."
#        [ "$TS_DEBUG" = true ] && echo -e "
#        [DEBUG]
#        command: \"bash $script_dir/$EDIT_HA_REGION_CONFIG -suffix -u $SSH_USER| tail -n1
#        "
#        bmc_suffix=$(bash $script_dir/$EDIT_HA_REGION_CONFIG -suffix -u $SSH_USER| tail -n1)
#        [[ -z $bmc_suffix ]] && { printf "%40s\n" "${red}variable bmc_suffix id empty${normal}"; exit 1; }
##        bmc_suffix=$BMC_SUFFIX
#      else
#        bmc_suffix=$BMC_SUFFIX
#      fi
##      echo "bmc_suffix: $bmc_suffix"
##      bmc_suffix=$BMC_SUFFIX
#      echo "bmc_suffix: $bmc_suffix"
##      BMC_HOST_NAME=$HOST_NAME$bmc_suffix
##      echo "BMC_HOST_NAME: $BMC_HOST_NAME"
#      [ "$TS_DEBUG" = true ] && echo -e "
#        [DEBUG]
#        command: \bmc_info=\$(bash "$utils_dir/$get_nodes_list_script" -suffix \"$bmc_suffix\" -nn \"$BMC_HOST_NAME\")
#        "
#      bmc_info=$(bash "$utils_dir/$get_nodes_list_script" -suffix "$bmc_suffix" -nn "$BMC_HOST_NAME")
#              [ "$TS_DEBUG" = true ] && echo -e "[DEBUG] bmc_info from get_nodes_list: $bmc_info"
#
#      if [[ -z "$bmc_info" ]] || [[ "$bmc_info" == *"unresolved"* ]]; then
#          echo -e "${red}ERROR: Failed to resolve BMC IP for $bmc_hostname${normal}"
#          echo -e "${yellow}Check if $bmc_hostname exists in /etc/hosts${normal}"
#          exit 1
#      fi
#
#      IPMI_IP="${bmc_info#*:}"
#      BMC_HOST_NAME="$bmc_hostname"
#
#      echo "BMC_HOST_NAME: $BMC_HOST_NAME"
#      echo "IPMI_IP: $IPMI_IP"
#    fi
#    check_connection_to_ipmi
#    case $POWER_STATE in
#      check)
#        python_script_execute check
#        ;;
#      on|start)
#        start_command
#        ;;
#      off)
#        actual_power_state=$(python_script_execute check| tail -n1)
#        echo "Actual ipmi satus: $actual_power_state"
#        if [ "$actual_power_state" = "PowerState.ON" ]; then
#          python_script_execute off
#        fi
#        ;;
#      restart)
#        python_script_execute restart
#        ;;
#      shutdown)
#        actual_power_state=$(python_script_execute check| tail -n1)
#        echo "Actual ipmi satus: $actual_power_state"
#        if [ "$actual_power_state" = "PowerState.ON" ]; then
#          python_script_execute shutdown
#        fi
#        ;;
#      *)
#        echo "Unknown power state parameter: $POWER_STATE"
#        return 1
#        ;;
#    esac
#}

# Get ssh user
get_ssh_user () {
    # Determine SSH user
    if [[ -z "$SSH_USER" ]]; then
        SSH_USER=$(whoami 2>/dev/null) || {
            echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
            SSH_USER="$default_ssh_user"
        }
    fi

    # Final user validation
    if [[ -z "$SSH_USER" ]]; then
        echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
        exit 1
    fi
}


# Main execution

# Determine SSH user
get_ssh_user

[ -z "$HOST_NAME" ] && [ -z "$IPMI_IP" ] && { echo "Host name or IP needed as env (HOST_NAME or IPMI_IP) or first start script parameter"; exit 1; }
check_module_exist
start_python_power_management_script


