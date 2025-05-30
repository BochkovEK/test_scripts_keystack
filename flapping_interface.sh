#!/bin/bash

#Colors
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
green=$(tput setaf 2)
default_interface_name="eth0"
default_number_of_cycle=20
default_sleep_time=5

[[ -z $TS_NUMBER_OF_CYCLES ]] && TS_NUMBER_OF_CYCLES=$default_number_of_cycle
[[ -z $TS_SLEEP_TIME ]] && TS_SLEEP_TIME=$default_sleep_time

echo "Start flapping interface test script..."
echo -e "${yellow}[WARNING]: This script must be executed on the node where the interface is being disabled(flapping).${normal}"

# Определение имени интерфейса
if [ -z "$1" ]; then
    if [ -z "$TS_INTERFACE_NAME" ]; then
      echo "Interface name can be defined either as argument or environment variable 'TS_INTERFACE_NAME'"
      TS_INTERFACE_NAME=$default_interface_name
      echo "Interface name is set by default: '$TS_INTERFACE_NAME'"
    else
      echo "Interface name is: '$TS_INTERFACE_NAME'"
    fi
else
  TS_INTERFACE_NAME=$1
  echo "Interface name is: '$TS_INTERFACE_NAME'"
fi

# Проверка существования интерфейса
if ! ip link show "$TS_INTERFACE_NAME" &>/dev/null; then
    echo -e "${red}[ERROR]: Interface $TS_INTERFACE_NAME does not exist!${normal}"
    echo "Available interfaces:"
    ip -o link show | awk -F': ' '{print $2}'
    exit 1
fi

# Функция для проверки статуса интерфейса
check_interface_status() {
    local status
    status=$(ip -o link show "$TS_INTERFACE_NAME" | awk '{print $9}')
    if [[ "$status" == "UP" ]]; then
        echo -e "${green}Current status: $TS_INTERFACE_NAME is UP${normal}"
    else
        echo -e "${red}Current status: $TS_INTERFACE_NAME is DOWN${normal}"
    fi
}

# Вывод текущего статуса интерфейса
check_interface_status

echo "Start flapping with the following parameters?
  TS_INTERFACE_NAME:    $TS_INTERFACE_NAME
  TS_NUMBER_OF_CYCLES:  $TS_NUMBER_OF_CYCLES
  TS_SLEEP_TIME:        $TS_SLEEP_TIME
"
read -p "Press enter to continue: "

for (( c=1; c<=${TS_NUMBER_OF_CYCLES}; c++ )); do
        echo "Cycle $c/$TS_NUMBER_OF_CYCLES"
        echo "Bringing interface $TS_INTERFACE_NAME down"
        ip link set $TS_INTERFACE_NAME down
        check_interface_status
        sleep $TS_SLEEP_TIME

        echo "Bringing interface $TS_INTERFACE_NAME up"
        ip link set $TS_INTERFACE_NAME up
        check_interface_status
        sleep $TS_SLEEP_TIME

        date
        echo "-------------------------------------"
done

echo "Finish"