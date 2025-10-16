#!/bin/bash

# The script read inventory file and convert it to hosts string
# To start:
# bash ~/test_scripts_keystack/inventory_to_hosts.sh <path_to_inventory_file>
# output "hosts_add_strings"

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")

# Constants
env_file_name=".inventory_to_hosts_env"
parse_inventory_script="parse_inventory.py"
yes_no_answer_script="yes_no_answer.sh"
inventory_file_name="inventory"
output_file_name="hosts_add_strings"
default_internal_prefix="internal"
default_external_prefix="external"
default_region_name="stand-name"
default_domain_name="vm.lab.itkey.com"
gitlab_short_name="ks-lcm"
add_strings="# ------ ADD strings ------"

# External scripts array
external_scripts=(
    "$script_dir/utils/$yes_no_answer_script"
)

# Colors
red=$(tput setaf 1)
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)

# Default values with fallback
[[ -z $INVENTORY_FILE_NAME ]] && INVENTORY_FILE_NAME="$inventory_file_name"
[[ -z $OUTPUT_FILE_NAME ]] && OUTPUT_FILE_NAME="$output_file_name"
[[ -z $DOMAIN ]] && DOMAIN=""
[[ -z $REGION ]] && REGION=""
[[ -z $INT_PREF ]] && INT_PREF=""
[[ -z $EXT_PREF ]] && EXT_PREF=""
[[ -z $GITLAB_SHORT_NAME ]] && GITLAB_SHORT_NAME="$gitlab_short_name"
[[ -z $ADD_STRINGS ]] && ADD_STRINGS="$add_strings"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $VIRTUAL_ENV ]] && VIRTUAL_ENV="$script_dir"
[[ -z $INVENTORY_PATH ]] && INVENTORY_PATH="$VIRTUAL_ENV/$inventory_file_name"
[[ -z $OUTPUT_FILE_PATH ]] && OUTPUT_FILE_PATH="$VIRTUAL_ENV/$output_file_name"

# Required variables for Python script
REQUIRED_VARS=("INVENTORY_PATH" "OUTPUT_FILE_PATH" "DOMAIN" "REGION" "INT_PREF" "EXT_PREF" "GITLAB_SHORT_NAME")

# Function to load external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            echo -e "${red}Error: Required script not found: $script_path${normal}"
            exit 1
        fi
        source "$script_path"
    done
}

# Function to display help information
show_help() {
    echo -E "
    The script parse inventory file to create $OUTPUT_FILE_PATH file like 'hosts' or add strings to hosts
    'inventory' file like this:
      kolla_internal_address=10.224.138.67
      external_floating=10.224.138.68
      [add_vm]
      qa-stable-ubuntu-add_vm-01 ansible_host=10.224.138.82
      [compute]
      qa-stable-ubuntu-comp-01 ansible_host=10.224.138.86
      qa-stable-ubuntu-comp-02 ansible_host=10.224.138.74
      [control]
    'hosts' file or strings in file hosts like this:
      10.224.130.3 int.ebochkov.test.domain backend.int.ebochkov.test.domin
      10.224.130.4 ext.ebochkov.test.domain backend.ext.ebochkov.test.domin

      10.224.130.9 ebochkov-keystack-lcm-01 lcm-01 nexus.test.domain lcm-nexus.test.domain netbox.test.domain gitlab.test.domain vault.test.domain

      10.224.130.7 ebochkov-keystack-add_vm-01 add_vm-01
      10.224.130.13 ebochkov-keystack-comp-01 comp-01
      10.224.130.17 ebochkov-keystack-comp-02 comp-02

    Options:
      -o, -output_file  <output_file_name> default: $output_file_name
      -d, -domain       <domain_name> example: test.domain
      -r, -region       <region_name> example: ebochkov
      -i, -inventory    <path_to_inventory_file> default: $INVENTORY_PATH
      -int_pref         <internal_prefix_for_internal_FQDN> example 'int' default: internal
      -ext_pref         <external_prefix_for_internal_FQDN> example 'ext' default: external
      -gitlab_name      <gitlab_short_name> default: ks-lcm
      -v, -debug        Enable debug output
      --help            Show this help message
    "
}

# Parse command line arguments
parse_arguments() {
    while [ -n "$1" ]; do
        case "$1" in
            -d|-domain)
                DOMAIN="$2"
                echo "Found the -domain option, with parameter value $DOMAIN"
                shift
                ;;
            -r|-region)
                REGION="$2"
                echo "Found the -region option, with parameter value $REGION"
                shift
                ;;
            -i|-inventory)
                INVENTORY_PATH="$2"
                echo "Found the -inventory option, with parameter value $INVENTORY_PATH"
                shift
                ;;
            -o|-output_file)
                OUTPUT_FILE_PATH="$2"
                echo "Found the -output_file option, with parameter value $OUTPUT_FILE_PATH"
                shift
                ;;
            -int_pref)
                INT_PREF="$2"
                echo "Found the -int_pref option, with parameter value $INT_PREF"
                shift
                ;;
            -ext_pref)
                EXT_PREF="$2"
                echo "Found the -ext_pref option, with parameter value $EXT_PREF"
                shift
                ;;
            -gitlab_name)
                GITLAB_SHORT_NAME="$2"
                echo "Found the -gitlab_name option, with parameter value $GITLAB_SHORT_NAME"
                shift
                ;;
            -v|-debug)
                TS_DEBUG="true"
                echo "Found the -debug option, with parameter value true"
                ;;
            --help)
                show_help
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$1 is not an option"
                ;;
        esac
        shift
    done
}

# Validate inventory file
validate_inventory_file() {
    if [ ! -f "$INVENTORY_PATH" ]; then
        echo -e "${yellow}Inventory file $INVENTORY_PATH not found - WARNING${normal}"
        echo -e "Create it or specify -i key, or environment var 'INVENTORY_PATH' ${normal}"
        echo -e "${red}The script cannot be executed - ERROR${normal}"
        exit 1
    fi

    if [ "$TS_DEBUG" = "true" ]; then
        echo "Inventory file content:"
        cat "$INVENTORY_PATH"
    fi
}

# Save variables to environment file
save_variables_to_file() {
    echo "Saving variables to ${env_file_name}..."
    > "${VIRTUAL_ENV}/$env_file_name"
    for var in "${REQUIRED_VARS[@]}"; do
        echo "export ${var}=\"${!var}\"" >> "${VIRTUAL_ENV}/$env_file_name"
    done
}

# Check and set required variables
check_and_set_variables() {
    local missing_vars=()

    # Check for missing required variables
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    # If missing variables found
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "Some required environment variables are not set: ${missing_vars[*]}"

        # Try to load from environment file
        if [[ -f "${VIRTUAL_ENV}/$env_file_name" ]]; then
            echo -e "${yellow}Loading variables from ${env_file_name}${normal}"
            source "${VIRTUAL_ENV}/${env_file_name}"

            # Re-check after loading
            missing_vars=()
            for var in "${REQUIRED_VARS[@]}"; do
                if [[ -z "${!var}" ]]; then
                    missing_vars+=("$var")
                fi
            done
        fi

        # If still missing, prompt user
        if [ ${#missing_vars[@]} -gt 0 ]; then
            echo "Please provide the following required variables:"
            for var in "${missing_vars[@]}"; do
                local default_value=""
                case "$var" in
                    "INVENTORY_PATH") default_value="$VIRTUAL_ENV/$inventory_file_name" ;;
                    "OUTPUT_FILE_PATH") default_value="$VIRTUAL_ENV/$output_file_name" ;;
                    "INT_PREF") default_value="$default_internal_prefix" ;;
                    "EXT_PREF") default_value="$default_external_prefix" ;;
                    "REGION") default_value="$default_region_name" ;;
                    "DOMAIN") default_value="$default_domain_name" ;;
                    "GITLAB_SHORT_NAME") default_value="ks-lcm" ;;
                esac

                read -rp "Enter $var [$default_value]: " value
                value="${value:-$default_value}"

                if [ -z "$value" ]; then
                    echo -e "${red}Error: $var is required - cannot be empty${normal}"
                    exit 1
                fi
                declare "$var=$value"
            done

            # Save variables for future use
            save_variables_to_file
        fi
    fi

    # Final validation
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo -e "${red}Error: Required variable $var is not set - ERROR${normal}"
            exit 1
        fi
    done

    # Debug output
    if [ "$TS_DEBUG" = "true" ]; then
        echo "
[DEBUG] Current variables:"
        for var in "${REQUIRED_VARS[@]}"; do
            echo "  $var: ${!var}"
        done
        read -p "Press enter to continue: "
    fi
}

# Check output file and confirm overwrite
check_output_file() {
    if [ -f "$OUTPUT_FILE_PATH" ]; then
        echo -e "${yellow}Output file already exists: $OUTPUT_FILE_PATH${normal}"

        if ! confirm_action_external "Overwrite existing file $OUTPUT_FILE_PATH?" "No"; then
            echo -e "${yellow}Operation cancelled by user${normal}"
            exit 0
        fi
    fi
}

# Execute Python script
python_script_execute() {
    echo "Start parsing $INVENTORY_PATH to hosts strings"

    # Export variables for Python script
    export OUTPUT_FILE_PATH="$OUTPUT_FILE_PATH"
    export DOMAIN="$DOMAIN"
    export REGION="$REGION"
    export GITLAB_SHORT_NAME="$GITLAB_SHORT_NAME"
    export INT_PREF="$INT_PREF"
    export EXT_PREF="$EXT_PREF"

    python3 "$script_dir/$parse_inventory_script" "$INVENTORY_PATH"
}

# Add entries to /etc/hosts
add_to_hosts() {
    local add_strings_already_exists
    add_strings_already_exists=$(grep -F "$ADD_STRINGS" /etc/hosts 2>/dev/null || true)

    if [ "$TS_DEBUG" = "true" ]; then
        echo "
[DEBUG]:
  add_strings_already_exists: $add_strings_already_exists
  OUTPUT_FILE_PATH: $OUTPUT_FILE_PATH
"
    fi

    if [ -z "$add_strings_already_exists" ]; then
        if [ "$TS_DEBUG" = "true" ]; then
            echo "
[DEBUG]:
  The lines from the file $OUTPUT_FILE_PATH will be added to the file /etc/hosts.
"
            read -p "Press enter to continue: "
        fi

        echo "$ADD_STRINGS" >> /etc/hosts
        cat "$OUTPUT_FILE_PATH" >> /etc/hosts
        echo "Updated /etc/hosts:"
        tail -n 20 /etc/hosts
    else
        echo -e "${yellow}Entries already exist in /etc/hosts, skipping addition${normal}"
    fi
}

# Main execution function
main() {
    echo "Starting inventory to hosts conversion..."

    # Load external scripts first
    load_external_scripts

    # Parse command line arguments
    parse_arguments "$@"

    # Validate inventory file
    validate_inventory_file

    # Check and set required variables
    check_and_set_variables

    # Check output file
    check_output_file

    # Execute Python script
    python_script_execute

    # Add to hosts file
    add_to_hosts

    echo -e "${green}Script completed successfully!${normal}"
    echo "Output file: $OUTPUT_FILE_PATH"
}

# Run main function
main "$@"