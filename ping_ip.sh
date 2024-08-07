#The script ping IP and send date to ping_states_with_$IP file. The script use WTD cycle. To end press Ctrl+C

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)

IP=$1
[[ -z ${IP} ]] && { printf "%40s\n" "${red}Pleas define IP with starter script parameters${normal}"; exit 1; }

echo -e "\n========= Start ping to $IP at $(date '+%d/%m/%Y %H:%M:%S') =========\n" >> $script_dir/ping_states_with_$IP.log

while true; do
  if ping -c 2 $IP &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $IP - success${normal}"
  else
    printf "%40s\n" "${red}No connection with $IP - error!${normal}"
    dt=$(date '+%d/%m/%Y %H:%M:%S')
    echo $dt >> $script_dir/ping_states_with_$IP.log
    echo "No connection with $IP - error!" >> $script_dir/ping_states_with_$IP.log
  fi
  sleep 1
done