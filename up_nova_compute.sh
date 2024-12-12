#!/bin/bash

# The script up nova compute

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)


script_name=$(basename "$0")
script_dir=$(dirname $0)
utils_dir=$script_dir/utils
openstack_utils=$utils_dir/openstack
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"

[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
#[[ -z $TRY_TO_RISE ]] && TRY_TO_RISE="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
#[[ -z $REGION ]] && REGION="region-ps"
#[[ -z $CHECK_IPMI ]] && CHECK_IPMI="true"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $ALL_COMPUTES ]] && ALL_COMPUTES="true"
[[ -z $NODES ]] && NODES=""

# Define parameters
define_parameters () {
  [ "$TS_DEBUG" = true ] && echo "[TS_DEBUG]: \"\$1\": $1"
  [ "$count" = 1 ] && [[ -n $1 ]] && { NODE_NAME=$1; echo "Command parameter found with value $NODE_NAME"; }
#  [ "$count" = 1 ] && [[ -n $1 ]] && { CHECK=$1; echo "Command parameter found with value $CHECK"; }
}

count=1
while [ -n "$1" ]
do
  case "$1" in
    --help) echo -E "
      -all                        try to rise nova compute service on all compute nodes
      -nn     -nodes_name         nodes name list for try to rise nova compute
      -v,     -debug              enabled debug output (without parameter)
      -dont_ask                   raise the nova compute service and do not ask

      To start:
        bash ~/test_keystack_scripts/$script_name ebochkov-ks-sber-comp-04
          or
        bash ~/test_keystack_scripts/$script_name -nn \"ebochkov-ks-sber-comp-04 ebochkov-ks-sber-comp-02\"
"
      exit 0
      break ;;
	  -all) ALL_COMPUTES="true"
	    echo "Found the -all parameter, with parameter value $ALL_COMPUTES"
      ;;
    -nn|-nodes_name) NODES="$2"
      ALL_COMPUTES="false"
	    echo "Found the -nodes_name <nodes_name_list> option, with parameter value $NODES"
      shift ;;
    -dont_ask) DONT_ASK="true"
	    echo "Found the -dont_ask, with parameter value $DONT_ASK"
      ;;
    -v|-debug) TS_DEBUG="true"
	    echo "Found the -debug, with parameter value $TS_DEBUG"
      ;;
    --) shift
      break ;;
    *) { echo "Parameter #$count: $1"; define_parameters "$1"; count=$(( $count + 1 )); };;
  esac
  shift
done


# Check openrc file
Check_and_source_openrc_file () {
  echo -e "${violet}Check openrc file...${normal}"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    echo -e "${green}$openrc_file file exist - success${normal}"
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    echo -e "${red}openrc file not found in $openrc_file${normal} - ERROR"
    exit 1
  fi
}

# Сheck openstack cli
Check_openstack_cli () {

  if [[ $CHECK_OPENSTACK = "true" ]]; then
#    echo -e "${violet}Check openstack cli...${normal}"
    if ! bash $utils_dir/$check_openstack_cli_script; then
      echo -e "${red}Failed to check openstack cli - ERROR${normal}"
      exit 1
    fi
  fi
}

# Check nova srvice list
Check_nova_srvice_list () {
  printf "%s\n" "${violet}Check nova srvice list...${normal}"
  printf "%s\n" "${yellow}openstack compute service list${normal}"
  nova_state_list=$(openstack compute service list)
  echo "$nova_state_list" | \
    sed --unbuffered \
      -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
      -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
      #-e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
}

# Check disabled computes in nova
Check_disabled_computes_in_nova () {
  printf "%s\n" "${violet}Check disabled computes in nova...${normal}"
  if [ "$ALL_COMPUTES" = true ] ; then
    cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')
  elif [ -n "$NODES" ]; then
    cmpt_disabled_nova_list=$NODES
  else
    echo -e "${red}Nodes list to try raise nova compute service is empty - ERROR${normal}"
    exit 1
  fi

  if [ "$DONT_ASK" = false ] ; then
    for cmpt in $cmpt_disabled_nova_list; do
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
#            echo $yes_no_input
      if [ "$yes_no_input" = "true" ]; then
        try_to_rise="true"
        export CHECK_OPENSTACK="false"
        export COMP_NODE_NAME=$cmpt
        export CHECK_AFTER="false"
        bash $openstack_utils/try_to_rise_node.sh
      fi
    done
    if [ "$try_to_rise" = "true" ]; then
      Check_nova_srvice_list
    fi
  fi
}


Check_and_source_openrc_file
Check_openstack_cli
Check_nova_srvice_list
Check_disabled_computes_in_nova

openstack compute service set --enable --up ebochkov-ks-sber-comp-04 nova-compute