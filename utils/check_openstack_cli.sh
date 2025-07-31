#The Script check openstack cli or install openstack cli

# check in stands nexus
# https://nexus.qa-stable-sberlinux.vm.lab.itkey.com/#browse/browse:k-pip

# Example install from public installation:
# export FROM_PUBLIC=true
# bash ~/test_scripts_keystack/utils/check_openstack_cli.sh

public_repo="https://pypi.org/simple/"

#Colors:
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

[[ -z $OSC_VERSION ]] && OSC_VERSION="6.6.1"
[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $DONT_INSTALL ]] && DONT_INSTALL="true"
[[ -z $FROM_PUBLIC ]] && FROM_PUBLIC="false"


osc_version_string="==$OSC_VERSION"

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
    if [ "$DONT_ASK" = "false" ]; then
      while true; do
        read -p "Do you want to try to install openstack cli [Yes]: " yn
        yn=${yn:-"Yes"}
        echo $yn
        case $yn in
          [Yy]* ) yes_no_input="true"; break;;
          [Nn]* ) yes_no_input="false"; break ;;
          * ) echo "Please answer yes or no.";;
        esac
      done
    else
      if [ "$DONT_INSTALL" = "false" ]; then
        yes_no_input=true
      fi
    fi
    if [ "$yes_no_input" = "true" ]; then
      [[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })
      if [ "$FROM_PUBLIC" = "true" ]; then
        from_public="-i $public_repo"
      fi
      case $os in
        sberlinux)
          yum install -y python3-pip
          python3 -m pip install $from_public python-openstackclient$osc_version_string
#          python3 -m pip install openstackclient
          path_sting_in_bashrc=$(cat $HOME/.bashrc|grep 'export PATH=\$PATH:/usr/local/bin')
          if [ -f /usr/local/bin/openstack ]; then
            if [ -z $path_sting_in_bashrc ]; then
              echo "export PATH=\$PATH:/usr/local/bin" >> $HOME/.bashrc
            fi
            echo
            printf "%s\n" "${yellow}You will need to source your .bashrc or logout/login to openstack installation complete${normal}"
            exit 1
          else
            printf "%s\n" "${red}Openstack cli failed to install - ERROR${normal}"
            exit 1
          fi
          ;;
        ubuntu)
          python3 -m pip install $from_public python-openstackclient$osc_version_string
          check_command openstack
            if [ -z $command_exist ]; then
              printf "%s\n" "${red}Openstack cli failed to install - ERROR${normal}"
              exit 1
            fi
#          echo "Coming soon..."
          ;;
        *)
          echo "There is no provision for openstack cli to be installed on the $os operating system."
          ;;
      esac
    else
      printf "%s\n" "${red}Openstack cli not installed - ERROR${normal}"
      exit 1
    fi
  else
    printf "%s\n" "${green}'openstack' command is available - success${normal}"
  fi
}

check_openstack_cli