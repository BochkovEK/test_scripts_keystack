# The power management script

[[ -z $HOST_NAME ]] && HOST_NAME=""
[[ -z $POWER_STATE ]] && POWER_STATE="on"
#=============================================

# Define parameters
define_parameters () {
  [ "$count" = 1 ] && [[ -n $1 ]] && { HOST_NAME=$1; echo "Host name parameter found with value $HOST_NAME"; }
  [ "$count" = 2 ] && [[ -n $1 ]] && { $POWER_STATE=$1; echo "Power state parameter found with value $POWER_STATE"; }
}

count=1
while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        The power management script
        -host_name,   -h  <host_name>     Host name for power management
        -power_state, -p  <power_state>   on, off, restart
        "
          exit 0
          break ;;
        -host_name|-h) HOST_NAME="$2"
          echo "Found the -host_name <host_name> option, with parameter value $HOST_NAME"
          shift ;;
        --) shift
          break ;;
        *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
        esac
        shift
done



