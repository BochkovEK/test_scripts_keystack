#!/bin/bash

# Yes/No Answer Script
# Can be used both as module (sourced) and standalone script

# Color definitions
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NORMAL=$(tput sgr0)
BLUE=$(tput setaf 4)
#RED=$(tput setaf 1)

# Default values
TS_DEBUG=${TS_DEBUG:-"false"}
TS_YES_NO_QUESTION=${TS_YES_NO_QUESTION:-"Please answer yes or no"}

# Main confirmation function
confirm_action_external() {
    local message="${1:-$TS_YES_NO_QUESTION}"
    local answer=""

    [ "$TS_DEBUG" = "true" ] && echo -e "${BLUE}[DEBUG] Question: $message${NORMAL}"

    while true; do
        read -rp "$message [y/N]: " answer

        # Handle empty input (default to No)
        if [ -z "$answer" ]; then
            echo -e "${YELLOW}Skipped${NORMAL}"
            return 1
        fi

        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                echo -e "${GREEN}Confirmed${NORMAL}"
                return 0
                ;;
            [Nn]|[Nn][Oo])
                echo -e "${YELLOW}Skipped${NORMAL}"
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# If script is executed directly (not sourced), run as standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments for standalone mode
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                TS_DEBUG="true"
                shift
                ;;
            --question)
                TS_YES_NO_QUESTION="$2"
                shift 2
                ;;
            -q)
                TS_YES_NO_QUESTION="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS] [MESSAGE]"
                echo ""
                echo "Options:"
                echo "  --debug          Enable debug output"
                echo "  --question TEXT  Set default question text"
                echo "  -q TEXT          Set default question text (short)"
                echo "  --help           Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 \"Do you want to continue?\""
                echo "  $0 --question \"Custom question\""
                echo "  $0 --debug -q \"Debug question\""
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # Use provided message as question
                confirm_action_external "$1"
                exit $?
                ;;
        esac
    done

    # If no arguments provided, use default question
    confirm_action_external
    exit $?
fi