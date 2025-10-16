#!/bin/bash

# SSH User Detection Module
# Can be used both as module (sourced) and standalone script

# Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 6)

# Default values
DEFAULT_SSH_USER=${DEFAULT_SSH_USER:-"root"}
TS_DEBUG=${TS_DEBUG:-"false"}

# Main function to get SSH user
get_ssh_user() {
    local preferred_user="${1:-$SSH_USER}"
    local default_user="${2:-$DEFAULT_SSH_USER}"

    [ "$TS_DEBUG" = "true" ] && echo -e "${blue}[DEBUG] get_ssh_user: preferred_user=$preferred_user, default_user=$default_user${normal}" >&2

    # If SSH_USER is already set, use it
    if [[ -n "$preferred_user" ]]; then
        echo "$preferred_user"
        return 0
    fi

    # Try to detect current user
    local detected_user
    detected_user=$(whoami 2>/dev/null) || {
        echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
        detected_user=""
    }

    # Use detected user or fallback to default
    if [[ -n "$detected_user" ]]; then
        echo "$detected_user"
        return 0
    else
        echo -e "${yellow}Warning: Using default SSH user: $default_user${normal}" >&2
        echo "$default_user"
        return 1
    fi
}

# Function to validate SSH user
validate_ssh_user() {
    local ssh_user="$1"

    if [[ -z "$ssh_user" ]]; then
        echo -e "${red}Error: SSH user cannot be empty!${normal}" >&2
        return 1
    fi

    # Basic validation - user should not contain special characters
    if [[ ! "$ssh_user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        echo -e "${red}Error: Invalid SSH user format: $ssh_user${normal}" >&2
        return 1
    fi

    return 0
}

# Function to get and validate SSH user
get_and_validate_ssh_user() {
    local preferred_user="${1:-$SSH_USER}"
    local default_user="${2:-$DEFAULT_SSH_USER}"

    local ssh_user
    ssh_user=$(get_ssh_user "$preferred_user" "$default_user")

    if validate_ssh_user "$ssh_user"; then
        echo "$ssh_user"
        return 0
    else
        return 1
    fi
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments for standalone mode
    while [[ $# -gt 0 ]]; do
        case $1 in
            --preferred-user)
                preferred_user="$2"
                shift 2
                ;;
            --default-user)
                default_user="$2"
                shift 2
                ;;
            --debug)
                TS_DEBUG="true"
                shift
                ;;
            --validate)
                validate_only="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --preferred-user USER  Preferred SSH user"
                echo "  --default-user USER    Default SSH user (default: root)"
                echo "  --debug               Enable debug output"
                echo "  --validate            Only validate user format"
                echo "  --help                Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 --preferred-user myuser"
                echo "  $0 --default-user admin"
                echo "  echo \$USER | $0 --validate"
                exit 0
                ;;
            *)
                # Treat as preferred user
                preferred_user="$1"
                shift
                ;;
        esac
    done

    if [[ "$validate_only" = "true" ]]; then
        read -r user_to_validate
        if validate_ssh_user "$user_to_validate"; then
            echo -e "${green}Valid SSH user: $user_to_validate${normal}"
            exit 0
        else
            exit 1
        fi
    fi

    # Get and output SSH user
    ssh_user=$(get_and_validate_ssh_user "$preferred_user" "$default_user")
    if [[ $? -eq 0 ]]; then
        echo "$ssh_user"
        exit 0
    else
        exit 1
    fi
fi