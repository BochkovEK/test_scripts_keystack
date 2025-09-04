#!/bin/bash

# Script for handling yes/no questions with default values
# Usage: source this script or call as function

[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $TS_YES_NO_QUESTION ]] && TS_YES_NO_QUESTION="Please answer yes or no [Yes]:"

# Function to handle yes/no questions
yes_no_answer() {
    local question="${1:-$TS_YES_NO_QUESTION}"
    local default_answer="${2:-"Yes"}"
    local answer=""

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Question: $question (default: $default_answer)"

    while true; do
        read -rp "$question" answer
        answer="${answer:-$default_answer}"

        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                echo "true"
                break
                ;;
            [Nn]|[Nn][Oo])
                echo "false"
                break
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    result=$(yes_no_answer "$@")
    echo "$result"
fi