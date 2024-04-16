# The power management script
# Example start:
#  bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 check
#  bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 on

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

required_modules=(
            #foo
            "sushy"
            "sys"
)

script_dir=$(dirname $0)

[[ -z $HOST_NAME ]] && HOST_NAME=""
[[ -z $POWER_STATE ]] && POWER_STATE="on"
[[ -z $USER_NAME ]] && USER_NAME=""
[[ -z $PASSWORD ]] && PASSWORD=""
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $EDIT_HA_REGION_CONFIG ]] && EDIT_HA_REGION_CONFIG="edit_ha_region_config.sh"
#[[ -z $POSTFIX ]] && POSTFIX="rmi"
#=============================================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { HOST_NAME=$1; echo "Host name parameter found with value: \"$HOST_NAME\""; }
  [ "$count" = 2 ] && [[ -n $1 ]] && { POWER_STATE=$1; echo "Power state parameter found with value: \"$POWER_STATE\""; }
  [ "$count" = 3 ] && [[ -n $1 ]] && { USER_NAME=$1; echo "User name parameter found with value: \"$USER_NAME\""; }
  [ "$count" = 4 ] && [[ -n $1 ]] && { PASSWORD=$1; echo "Password parameter found with value: \"$PASSWORD\""; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
  --help) echo -E "
    The power management script
      -hv, -host_name,       <host_name>     Host name for power management (ipmi)
      -p,  -power_state      <power_state>   check, on, off, restart
      -v,  -debug  enabled debug output (without parameter)

      Example to start script:
           bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 check
           bash baremetal_power_management.sh ebochkov-ks-sber-comp-05 on
"
#-pf, -postfix          <postfix>       Postfix for host name power management (ipmi; example: rmi)

    exit 0
    break ;;
  -hv|-host_name) HOST_NAME="$2"
    echo "Found the -host_name <host_name> option, with parameter value $HOST_NAME"
    shift ;;
  -u|-user_name) HOST_NAME="$2"
    echo "Found the -user_name <host_name> option, with parameter value $USER_NAME"
    shift ;;
  -pswd|-password) PASSWORD="$2"
    echo "Found the -password <host_name> option, with parameter value $PASSWORD"
    shift ;;
  -v|-debug) DEBUG="true"
	  echo "Found the -debug, with parameter value $DEBUG"
    ;;
  -p|-power_state) POWER_STATE="$2"
	  echo "Found the -power_state, with parameter value $POWER_STATE"
    shift ;;
  --) shift
      break ;;
  *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
   esac
   shift
done

# Check openrc file
Check_openrc_file () {
    echo "Check openrc file here: $OPENRC_PATH"
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    #echo $OPENRC_PATH
    #echo $check_openrc_file
    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }
}

check_connection_to_ipmi () {
  echo "Check connection to $BMC_HOST_NAME"
  if ping -c 2 $BMC_HOST_NAME &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $BMC_HOST_NAME - success${normal}"
  else
    printf "%40s\n" "${red}No connection with $BMC_HOST_NAME - error!${normal}"
    exit 1
  fi
}

check_module_exist () {
  for module in "${required_modules[@]}"; do
    module_exists=$(pip list| grep module)

    [ "$DEBUG" = true ] && echo -e "
    [DEBUG]: module: $module
    [DEBUG]: module_exists: $module_exists
  "

    [ -z "$module_exists" ] && { echo "Install $module"; pip install $module; }
  done
}

python_script_execute () {
  echo "Send command $1 to $BMC_HOST_NAME"
  python3 $script_dir/redfish_manager.py $BMC_HOST_NAME $1 $USER_NAME $PASSWORD
}

start_python_power_management_script () {
    echo "Check power state parameter: $POWER_STATE..."
    bmc_suffix=$(bash $script_dir/$EDIT_HA_REGION_CONFIG suffix| tail -n1)
    [[ -z $bmc_suffix ]] && { printf "%40s\n" "${red}variable bmc_suffix id empty${normal}"; exit 0; }
    echo "bmc_suffix: $bmc_suffix"
    BMC_HOST_NAME=$HOST_NAME$bmc_suffix
    echo "BMC_HOST_NAME: $BMC_HOST_NAME"
    check_connection_to_ipmi
    case $POWER_STATE in
      check)
        python_script_execute check
        ;;
      on)
        actual_power_state=$(python_script_execute check| tail -n1)
        echo "Actual ipmi satus: $actual_power_state"
        if [ "$actual_power_state" = "PowerState.OFF" ]; then
          Check_openrc_file
          source $OPENRC_PATH
#          comp_host_name=$(echo "${HOST_NAME%%-*}")
          echo "Trying set --disable-reason \"test disable\" to $HOST_NAME"
          openstack compute service set --disable --disable-reason "test disable" $HOST_NAME nova-compute
          echo "Trying set power state \"on\" on $HOST_NAME"
          sent_launch_command=$(python_script_execute on)
          [ "$sent_launch_command" = "None" ] && { echo "The host: $HOST_NAME startup command has been successfully sent"; }
        fi
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
      *)
        echo "Unknown power state parameter: $POWER_STATE"
        return 1
        ;;
    esac
}


[ -z "$HOST_NAME" ] && { echo "Host name needed as env (HOST_NAME) or first start script parameter"; exit 1; }
check_module_exist
start_python_power_management_script


