#The script ping IP and send date to ping_states_with_$IP file. The script use WTD cycle. To end press Ctrl+C

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)

IP=$1
[[ -z ${IP} ]] && { echo "Pleas define IP with starter script parameters"; exit 1; }

while true; do
  if ping -c 2 $IP &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $IP - success${normal}"
  else
    printf "%40s\n" "${red}No connection with $IP - error!${normal}" >> $script_dir/ping_states_with_$IP
    dt=$(date '+%d/%m/%Y %H:%M:%S')
    echo $dt >> $script_dir/ping_states_with_$IP
    echo "No connection with $IP - error!" >> $script_dir/ping_states_with_$IP
  fi
done