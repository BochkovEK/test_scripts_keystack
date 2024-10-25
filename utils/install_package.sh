#!/bin/bash

# The script check and install package
# Example: bash install_package.sh wget

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z "${1}" ]] && { echo -e "${red}Required package name as start parameter - ERROR${normal}"; exit 1; }

package_name=$1

yes_no_answer () {
  yes_no_input=""
  while true; do
    read -p "$yes_no_question" yn
    yn=${yn:-"Yes"}
    echo $yn
    case $yn in
        [Yy]* ) yes_no_input="true"; break;;
        [Nn]* ) yes_no_input="false"; break ;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  yes_no_question="<Empty yes\no question>"
}

# Check command
check_command () {
  echo "Check $1 command..."
  command_exist="foo"
  if ! command -v $1 &> /dev/null; then
    command_exist=""
  fi
}

# check wget
check_package () {
  echo "Check $package_name..."
  check_command $package_name
  #mock test
  #command_exist=""
  if [ -z $command_exist ]; then
    printf "%s\n" "${yellow}'$package_name' not installed!${normal}"
    yes_no_question="Do you want to try to install [Yes]: "
    yes_no_answer
    if [ "$yes_no_input" = "true" ]; then
      [[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })
      case $os in
        sberlinux)
          case $package_name in
            host)
              yum install -y "bind-utils"
              ;;
            *)
              yum install -y $package_name
              ;;
          esac
          check_command $package_name
          if [ -z $command_exist ]; then
            echo "For sberlinux try this command:"
            echo "yum install -y $package_name"
            printf "%s\n" "${red}$package_name not installed - ERROR${normal}"
            exit 1
          else
            printf "%s\n" "${green}'$package_name' command is available - success${normal}"
          fi
          ;;
          ubuntu)
            echo "Coming soon..."
            ;;
          *)
            echo "There is no provision for $package_name to be installed on the $os operating system."
            ;;
        esac
    else
      exit 1
    fi
  else
    printf "%s\n" "${green}'$package_name' command is available - success${normal}"
  fi
}

check_package