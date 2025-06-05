#The script ping IP and send date to ping_states_with_$IP file. The script use WTD cycle. To end press Ctrl+C
# log file path can be define by env PING_LOG_FILE

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)

#default_log_file="/tmp/ping_VM_$(date '+%Y-%m-%d').log"
#[[ -z $PING_LOG_FILE ]] && PING_LOG_FILE=$default_log_file

IP=$1
[[ -z ${IP} ]] && { printf "%40s\n" "${red}Pleas define IP with starter script parameters${normal}"; exit 1; }

function validate_ip() {
    grep -E -q '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' <<< "$1"
}

# Validate IP format
if ! validate_ip "$IP"; then
   printf "%40s\n" "${red}Error: Invalid IP address format${normal}" >&2
    exit 1
fi

[[ -z $PING_LOG_FILE ]] && PING_LOG_FILE="/tmp/ping_VM_${IP}_$(date '+%Y-%m-%d').log"

echo -e "\n========= Start ping to $IP at $(date '+%d/%m/%Y %H:%M:%S') =========\n" >> $PING_LOG_FILE

while true; do
  if ping -c 2 $IP &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $IP - success${normal}" >> $PING_LOG_FILE
  else
    printf "%40s\n" "${red}No connection with $IP - error!${normal}"
    dt=$(date '+%d/%m/%Y %H:%M:%S')
    echo $dt >> $script_dir/ping_states_with_$IP.log
    echo "No connection with $IP - error!" >> $PING_LOG_FILE
  fi
  sleep 1
done