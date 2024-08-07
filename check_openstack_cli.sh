#The Script check openstack cli or install openstack cli

#Colors:
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

# Check command
check_command () {
  echo "Check $1 command..."
  command_exist="foo"
  if ! command -v $1 &> /dev/null; then
    command_exist=""
  fi
}

# check openstack cli
check_openstack_cli () {
  printf "%s\n" "${violet}Check openstack cli...${normal}"
  check_command openstack
  if [ -z $command_exist ]; then
    echo -e "\033[31mOpenstack cli not installed\033[0m"
    while true; do
      read -p "Do you want to try to raise and enable nova service on $cmpt? [Yes]: " yn
      yn=${yn:-"Yes"}
      echo $yn
      case $yn in
        [Yy]* ) yes_no_input="true"; break;;
        [Nn]* ) yes_no_input="false"; break ;;
        * ) echo "Please answer yes or no.";;
      esac
    done
    if [ "$yes_no_input" = "true" ]; then
      [[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })
      case $os in
        sberlinux)
          yum install -y python3-pip
          python3 -m pip install openstackclient
          export PATH=\$PATH:/usr/local/bin
          ;;
        ubuntu)
          echo "Coming soon..."
          ;;
        *)
          echo "There is no provision for openstack cli to be installed on the $os operating system."
          ;;
      esac
    fi
  else
    printf "%s\n" "${green}'host' command is available - success${normal}"
  fi

  check_command openstack
    if [ -z $command_exist ]; then
      printf "%s\n" "${red}Openstack cli failed to install - error${normal}"
      exit 1
    fi
}

check_openstack_cli