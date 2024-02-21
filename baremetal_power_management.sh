# The power management script
# Example start:
#  bash baremetal_power_management.sh ebochkov-ks-sber-comp-05-rmi check
#  bash baremetal_power_management.sh ebochkov-ks-sber-comp-05-rmi on

required_modules=(
            #foo
            "sushy"
            "sys"
)

[[ -z $HOST_NAME ]] && HOST_NAME=""
[[ -z $POWER_STATE ]] && POWER_STATE="on"
[[ -z $USER_NAME ]] && USER_NAME=""
[[ -z $PASSWORD ]] && PASSWORD=""
#=============================================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { HOST_NAME=$1; echo "Host name parameter found with value $HOST_NAME"; }
  [ "$count" = 2 ] && [[ -n $1 ]] && { POWER_STATE=$1; echo "Power state parameter found with value $POWER_STATE"; }
  [ "$count" = 3 ] && [[ -n $1 ]] && { USER_NAME=$1; echo "User name parameter found with value $USER_NAME"; }
  [ "$count" = 4 ] && [[ -n $1 ]] && { PASSWORD=$1; echo "Password parameter found with value $PASSWORD"; }
}

count=1
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The power management script
        -host_name,   -h  <host_name>     Host name for power management (ipmi)
        -power_state, -p  <power_state>   check, on, off, restart
        Example to start script:
           bash baremetal_power_management.sh ebochkov-ks-sber-comp-05-rmi check
           bash baremetal_power_management.sh ebochkov-ks-sber-comp-05-rmi on
        "
          exit 0
          break ;;
        -host_name|-h) HOST_NAME="$2"
          echo "Found the -host_name <host_name> option, with parameter value $HOST_NAME"
          shift ;;
        -user_name|-u) HOST_NAME="$2"
          echo "Found the -user_name <host_name> option, with parameter value $USER_NAME"
          shift ;;
        -password|-pswd) PASSWORD="$2"
          echo "Found the -password <host_name> option, with parameter value $PASSWORD"
          shift ;;
        --) shift
          break ;;
        *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
        esac
        shift
done

check_parameters () {
  [ -z "$HOST_NAME" ] && { echo "Host name needed as env (HOST_NAME) or first start script parameter"; exit 1; }
}

check_module_exist () {
  for module in "${required_modules[@]}"; do
    module_exists=$(pip list| grep module)
    [ -z "$module_exists" ] && { echo "Install $module"; pip install $module; }
  done
}

start_python_power_management_script () {
  python3 ./baremetal_power_management.py $HOST_NAME $POWER_STATE $USER_NAME $PASSWORD
}

check_parameters
check_module_exist
start_python_power_management_script


