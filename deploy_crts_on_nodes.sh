#!/bin/bash

# The script for deploing pub keys from gitlab and lcm, nexus and docker crts, by IPs list or by hosts

cmpt_pattern="\-comp\-..$"
ctrl_pattern="\-ctrl\-..$"
net_pattern="\-net\-..$"
nodes_to_find="$cmpt_pattern|$ctrl_pattern|$net_pattern"

IPS_LIST=("<IP_1>" "<IP_2>" "<IP_3>" "...")

[[ -z $IPS ]] && IPS=( "${IPS_LIST[@]}" )
[[ -z $INSTALL_HOME ]] && INSTALL_HOME=/installer
[[ -z $SETTINGS ]] && SETTINGS=$INSTALL_HOME/config/settings
[[ -z $DEPLOY_BY_IPS_LIST ]] && DEPLOY_BY_IPS_LIST=false
[[ -z $DEPLOY_LCM_KEY ]] && DEPLOY_LCM_KEY=false
[[ -z $DEPLOY_GITLAB_KEY ]] && DEPLOY_GITLAB_KEY=true
[[ -z $DEPLOY_DOCKER_CFG ]] && DEPLOY_DOCKER_CFG=true
[[ -z $DEPLOY_NEXUS_CRTS ]] && DEPLOY_NEXUS_CRTS=true


while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -ih, 	-install_home		<install_home_dir>
        -s, 	-settings		    <path_settings_file>
        -l,   -by_list        <deploy_by_ips_list_bool>
        -gk,	-gitlab_key		  <deploy_gitlab_key_bool>
        -lk,	-lcm_key	  	  <deploy_lcm_key_bool>
        -dc,	-docker_cfg		  <deploy_docker_cfg_bool>
        -nc,	-nexus_crt		  <deploy_nexus_crt_bool>
        "
            exit 0
            break ;;
	      -ih|-install_home) INSTALL_HOME="$2"
	          echo "Found the -t <install_home_dir> option, with parameter value $INSTALL_HOME"
            shift ;;
        -s|-settings) SETTINGS="$2"
	          echo "Found the -t <path_settings_file> option, with parameter value $SETTINGS"
            shift ;;
        -l|-by_list) DEPLOY_BY_IPS_LIST="$2"
	          echo "Found the -t <deploy_by_ips_list_bool> option, with parameter value $DEPLOY_BY_IPS_LIST"
            shift ;;
       -gk|-gitlab_key) DEPLOY_GITLAB_KEY="$2"
	          echo "Found the -t <deploy_gitlab_key_bool> option, with parameter value $DEPLOY_GITLAB_KEY"
            shift ;;
        -lk|-lcm_key) DEPLOY_LCM_KEY="$2"
	          echo "Found the -t <deploy_lcm_key_bool> option, with parameter value $DEPLOY_LCM_KEY"
            shift ;;
        -dc|-docker_cfg) DEPLOY_DOCKER_CFG="$2"
	          echo "Found the -t <deploy_docker_cfg_bool> option, with parameter value $DEPLOY_DOCKER_CFG"
            shift ;;
        -nc|-nexus_crt) DEPLOY_NEXUS_CRTS="$2"
	          echo "Found the -t <deploy_nexus_crt_bool> option, with parameter value $DEPLOY_NEXUS_CRTS"
            shift ;;
        --) shift
            break ;;
        *) echo "$1 is not an option";;
        esac
        shift
done


deploy_and_copy () {
    if [ "DEPLOY_BY_IPS_LIST" = true ] ; then
        IPS_ARRAY=( "${IPS_LIST[@]}" )
    else
        IPS_ARRAY=$(cat /etc/hosts | grep -E ${nodes_to_find} | awk '{print $2}')
    fi
    #for IP in "${IPS[@]}"; do
    for IP in "${IPS_ARRAY[@]}"; do
      if [ "$DEPLOY_LCM_KEY" = true ] ; then
        echo "Copy public key from lcm to ${IP}"
        ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub $IP
      fi
      if [ "$DEPLOY_GITLAB_KEY" = true ] ; then
        echo "Copy gitlab key to ${IP}"
        KEY=$(cat $INSTALL_HOME/config/gitlab_key.pub)
        ssh -o StrictHostKeyChecking=no $IP echo '"$KEY"' >> ~/.ssh/authorized_keys
      fi
      if [ "$DEPLOY_NEXUS_CRTS" = true ] ; then
        echo "Deploy nexus crt to $IP"
        ssh -o StrictHostKeyChecking=no $IP mkdir -p /etc/docker/certs.d/nexus.$DOMAIN:5000
        scp -o StrictHostKeyChecking=no $INSTALL_HOME/data/ca/installer/certs/nexus.crt $IP:/etc/docker/certs.d/nexus.$DOMAIN:5000/nexus.crt
        ssh -o StrictHostKeyChecking=no $IP chmod 444 /etc/docker/certs.d/nexus.$DOMAIN:5000/nexus.crt
      fi
      if [ "$DEPLOY_DOCKER_CFG" = true ] ; then
        echo "Deploy docker cfg to $IP"
        ssh -o StrictHostKeyChecking=no $IP mkdir -p ~/.docker
        scp -o StrictHostKeyChecking=no $INSTALL_HOME/config/docker_auth.json $IP:~/.docker/config.json
        ssh -o StrictHostKeyChecking=no $IP chmod 600 ~/.docker/config.json
      fi
    done
}

read -p "Press enter to continue"

echo -E "
    Deploy by IPs list (false: by hosts):   $DEPLOY_BY_IPS_LIST
    Installer home dir:                     $INSTALL_HOME
    Deploy public key from lcm:             $DEPLOY_LCM_KEY
    Deploy gitlab key:                      $DEPLOY_GITLAB_KEY
    Deploy nexus crts:                      $DEPLOY_NEXUS_CRTS
    Deploy docker cfg:                      $DEPLOY_DOCKER_CFG
"
source $SETTINGS
deploy_and_copy
