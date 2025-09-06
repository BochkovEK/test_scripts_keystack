#!/bin/bash

# Script to check configuration files on nodes for [castellan_configsource] groups
# Loads configuration lists from external file

script_file_path=$(realpath "$0")
script_dir=$(dirname "$script_file_path")
default_ssh_user="root"
command_on_nodes_script_name="../command_on_nodes.sh"

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 13)
cyan=$(tput setaf 14)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#CHECK_COMP="false"
#CHECK_CTRL="false"
#CHECK_HASHED="false"
#CHECK_PROMETH="false"
#CHECK_ALL="true"
#CONFIG_LIST_FILE_PATH=""
#ENV_CONFIG_LIST=""
#SSH_USER="$default_ssh_user"

# Default values
[[ -z $CHECK_COMP ]] && CHECK_COMP="false"
[[ -z $CHECK_CTRL ]] && CHECK_CTRL="false"
[[ -z $CHECK_HASHED ]] && CHECK_HASHED="false"
[[ -z $CHECK_PROMETH ]] && CHECK_PROMETH="false"
[[ -z $CHECK_ALL ]] && CHECK_ALL="true"
[[ -z $CONFIG_LIST_FILE_PATH ]] && CONFIG_LIST_FILE_PATH=""
[[ -z $CONFIG ]] && CONFIG=""
#[[ -z $ENV_CONFIG_LIST ]] && ENV_CONFIG_LIST=""
#[[ -z $SSH_USER ]] && SSH_USER=$default_ssh_user

# Arrays for configuration files
declare -a control_config_list
declare -a compute_config_list
declare -a hashed_password_config_list
declare -a prometheus_exporters_config_list

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -comp                         Check configs on compute nodes
      -ctrl                         Check configs on control nodes
      -hashed                       Check hashed passwords in configs
      -prometheus                   Check prometheus exporters configs
      -c, config                    Check the specific config
      -l, -configs_list_file_path   <path> Check specific config file
      -u, -user                     <user> SSH username
      --help                        Show this help message

    Configs list file format:
      TS_CONTROL_CONFIG_LIST_0=/path/to/config1.conf
      TS_COMPUTE_CONFIG_LIST_0=/path/to/config2.conf
      TS_HASHED_PASSWORD_CONFIG_LIST_0=/path/to/config3.conf
    "
}
#      -e, -env_config_list <file> Load config lists from environment file

# Function to validate input parameters
validate_input() {
    if [ -z "$CONFIG" ] && [ -z "$CONFIG_LIST_FILE_PATH" ]; then
        echo -e "${red}ERROR: Either -c (config path) or -e (env config list) must be specified!${normal}"
        echo -e "${yellow}Please provide one of the following:${normal}"
        echo -e "  -c /path/to/config.conf    (check specific config file)"
        echo -e "  -l .configs_list.env       (load configs list from file)"
        show_help
        exit 1
    fi

    if [ -n "$CONFIG_LIST_FILE_PATH" ] && [ ! -f "$CONFIG_LIST_FILE_PATH" ]; then
        echo -e "${red}ERROR: Config list file not found: $CONFIG_LIST_FILE_PATH${normal}"
        exit 1
    fi

    if [ -n "$CONFIG" ] && [ "$CHECK_ALL" = "true" ] && [ "$CHECK_CTRL" = "false" ] && [ "$CHECK_COMP" = "false" ]; then
        echo -e "${yellow}WARNING: Checking specific config but no node type specified. Will check both control and compute nodes.${normal}"
    fi
}

# Function to load configuration lists from file
load_config_lists() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        echo -e "${red}Config file not found: $config_file${normal}"
        return 1
    fi

    # Clear existing arrays
    control_config_list=()
    compute_config_list=()
    hashed_password_config_list=()
    prometheus_exporters_config_list=()

    # Load configuration from file
    while IFS='=' read -r key value; do
        case "$key" in
            TS_CONTROL_CONFIG_LIST_*)
                control_config_list+=("$value")
                ;;
            TS_COMPUTE_CONFIG_LIST_*)
                compute_config_list+=("$value")
                ;;
            TS_HASHED_PASSWORD_CONFIG_LIST_*)
                hashed_password_config_list+=("$value")
                ;;
            TS_PROMETHEUS_EXPORTERS_CONFIG_LIST_*)
                prometheus_exporters_config_list+=("$value")
                ;;
        esac
    done < "$config_file"

    echo -e "${green}Loaded configuration from: $config_file${normal}"
    echo -e "${yellow}Control configs: ${#control_config_list[@]} files${normal}"
    echo -e "${yellow}Compute configs: ${#compute_config_list[@]} files${normal}"
    echo -e "${yellow}Hashed password configs: ${#hashed_password_config_list[@]} files${normal}"
}

# Parse command line arguments
while [ -n "$1" ]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;
        -comp)
            CHECK_COMP="true"
            CHECK_ALL="false"
            echo "Checking configs on compute nodes"
            ;;
        -ctrl)
            CHECK_CTRL="true"
            CHECK_ALL="false"
            echo "Checking configs on control nodes"
            ;;
        -hashed)
            CHECK_HASHED="true"
            CHECK_ALL="false"
            echo "Checking hashed passwords in configs"
            ;;
        -prometheus)
            CHECK_PROMETH="true"
            CHECK_ALL="false"
            echo "Checking prometheus exporters configs"
            ;;
        -c|-config)
            CONFIG="$2"
            echo "Checking specific config: $CONFIG"
            shift
            ;;
        -l|-configs_list_file_path)
            CONFIG_LIST_FILE_PATH="$2"
            echo "Checking configs from configs list file: $CONFIG_LIST_FILE_PATH"
            load_config_lists "$CONFIG_LIST_FILE_PATH"
            shift
            ;;
        -u|-user)
            SSH_USER="$2"
            echo "Using SSH user: $SSH_USER"
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
    shift
done

# Check if command script exists
if [ ! -f "$script_dir/$command_on_nodes_script_name" ]; then
    echo -e "${red}Script not found: $command_on_nodes_script_name${normal}"
    exit 1
fi

# Function to read and check configuration file
read_config() {
    local node_type="$1"
    local config_path="$2"
    local check_type="$3"

    echo -e "${cyan}Checking file $config_path on $node_type nodes${normal}"

    # Check if file exists
    bash "$script_dir/$command_on_nodes_script_name" -nt "$node_type" -u "$SSH_USER" \
        -c "sudo ls '$config_path' 2>/dev/null" | \
        sed --unbuffered \
            -e 's/\(.*No such file or directory.*\)/\o033[31m\1\o033[39m/'

    # Check for castellan configuration if requested
    if [ "$check_type" = "castellan" ]; then
        echo -e "${cyan}Checking for castellan configuration...${normal}"
        bash "$script_dir/$command_on_nodes_script_name" -u "$SSH_USER" -nt "$node_type" \
            -c "sudo cat '$config_path' 2>/dev/null | grep -E 'wsrep_sst_auth|auth-pass|requirepass|masterauth|db_uri|vault_secret|password_hash|with secret| password |\"password\"|password:|_pass\"|password =|\[castellan_configsource\]'" | \
            sed --unbuffered \
                -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - [castellan group exists]\o033[39m/' \
                -e 's/\(.*password_hash.*\)/\o033[32m...password_hash... - [password hash exists]\o033[39m/' \
                -e 's/\(.*vault_secret.*\)/\o033[32m...vault_secret... - [vault settings exist]\o033[39m/' \
                -e 's/\(.*with secret.*\)/\o033[32m...with secret... - [vault settings exist]\o033[39m/' \
                -e 's/\(.*password.*\)/\o033[33m\1 - [check password]\t\o033[39m/' \
                -e 's/\(.*auth-pass.*\)/\o033[33m\1 - [check password]\t\o033[39m/' \
                -e 's/\(.*wsrep_sst_auth.*\)/\o033[33m\1 - [check password]\t\o033[39m/' \
                -e 's/\(.*requirepass.*\)/\o033[33m\1 - [check password]\t\o033[39m/' \
                -e 's/\(.*masterauth.*\)/\o033[33m\1 - [check password]\t\o033[39m/' \
                -e 's/\(.*_pass\".*\)/\o033[33m\1 - [check password]\t\o033[39m/'
    fi
}

# Function to check configurations on control nodes
check_configs_on_controls() {
    if [ ${#control_config_list[@]} -eq 0 ]; then
        echo -e "${yellow}No control configs to check${normal}"
        return
    fi

    echo -e "${cyan}Checking [castellan_configsource] in control node configs${normal}"
    for config in "${control_config_list[@]}"; do
        echo -e "${violet}Checking: $config${normal}"
        read_config "ctrl" "$config" "castellan"
        echo "----------------------------------------"
    done
}

# Function to check configurations on compute nodes
check_configs_on_computes() {
    if [ ${#compute_config_list[@]} -eq 0 ]; then
        echo -e "${yellow}No compute configs to check${normal}"
        return
    fi

    echo -e "${cyan}Checking [castellan_configsource] in compute node configs${normal}"
    for config in "${compute_config_list[@]}"; do
        echo -e "${violet}Checking: $config${normal}"
        read_config "comp" "$config" "castellan"
        echo "----------------------------------------"
    done
}

# Function to check hashed password configurations
check_hashed_passwords() {
    if [ ${#hashed_password_config_list[@]} -eq 0 ]; then
        echo -e "${yellow}No hashed password configs to check${normal}"
        return
    fi

    echo -e "${cyan}Checking hashed passwords in configs${normal}"
    for config in "${hashed_password_config_list[@]}"; do
        echo -e "${violet}Checking: $config${normal}"
        read_config "ctrl" "$config" "castellan"
        echo "----------------------------------------"
    done
}

# Function to check specific configuration file
check_specific_config() {
    if [ -z "$CONFIG_PATH" ]; then
        echo -e "${red}No config path specified${normal}"
        return
    fi

    echo -e "${cyan}Checking specific config: $CONFIG_PATH${normal}"

    if [ "$CHECK_CTRL" = "true" ] || [ "$CHECK_ALL" = "true" ]; then
        read_config "ctrl" "$CONFIG_PATH" "castellan"
        echo "----------------------------------------"
    fi

    if [ "$CHECK_COMP" = "true" ] || [ "$CHECK_ALL" = "true" ]; then
        read_config "comp" "$CONFIG_PATH" "castellan"
        echo "----------------------------------------"
    fi
}

# Get ssh user
get_ssh_user () {
    # Determine SSH user
    if [[ -z "$SSH_USER" ]]; then
        SSH_USER=$(whoami 2>/dev/null) || {
            echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
            SSH_USER="$default_ssh_user"
        }
    fi

    # Final user validation
    if [[ -z "$SSH_USER" ]]; then
        echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
        exit 1
    fi
}

# Main execution

# Validate input parameters
validate_input

# Check if command script exists
if [ ! -f "$script_dir/$command_on_nodes_script_name" ]; then
    echo -e "${red}Script not found: $command_on_nodes_script_name${normal}"
    exit 1
fi

get_ssh_user

if [ -n "$CONFIG" ]; then
    check_specific_config
    exit 0
fi

if [ "$CHECK_COMP" = "true" ] || [ "$CHECK_ALL" = "true" ]; then
    check_configs_on_computes
fi

if [ "$CHECK_CTRL" = "true" ] || [ "$CHECK_ALL" = "true" ]; then
    check_configs_on_controls
fi

if [ "$CHECK_HASHED" = "true" ] || [ "$CHECK_ALL" = "true" ]; then
    check_hashed_passwords
fi