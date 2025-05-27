#!/bin/bash
set -euo pipefail

# --- Constants ---
SS_BIN="/usr/sbin/ss"
PGREP_BIN="/usr/bin/pgrep"
SUDO_BIN="/usr/bin/sudo"

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Input Validation ---
if [ $# -lt 2 ]; then
    echo "Usage: $0 <process-name> <port1> [port2 ...] [--run-as <username>]"
    echo "Example: $0 nginx 80 443 --run-as www-data"
    exit 1
fi

# --- Parse Arguments ---
process_name=$1
shift
ports=()
run_as_user=""

while [ $# -gt 0 ]; do
    case $1 in
        --run-as)
            shift
            run_as_user=$1
            ;;
        *)
            ports+=("$1")
            ;;
    esac
    shift
done

# --- Validate Ports ---
if [ ${#ports[@]} -eq 0 ]; then
    echo -e "${RED}Error: At least one port must be specified${NC}" >&2
    exit 1
fi

# --- Port Check Function ---
check_ports_as_user() {
    local user=$1
    local ports_pattern=${ports[*]// /|}
    local pids

    # Get PIDs as target user
    if [ "$user" = "$(whoami)" ]; then
        pids=$($PGREP_BIN -f "$process_name" | tr '\n' '|' | sed 's/|$//')
    else
        pids=$($SUDO_BIN -u "$user" $PGREP_BIN -f "$process_name" | tr '\n' '|' | sed 's/|$//')
    fi

    if [ -z "$pids" ]; then
        echo -e "${RED}Process '$process_name' not found running under user '$user'${NC}" >&2
        return 1
    fi

    # Get all TCP connections (not just listening)
    if [ "$user" = "$(whoami)" ]; then
        ss_output=$($SS_BIN -ntp)
    else
        ss_output=$($SUDO_BIN -u "$user" $SS_BIN -ntp 2>/dev/null || echo "SS command failed")
    fi

    # Filter all ports for this process (both local and remote)
    process_ports=$(echo "$ss_output" | grep -E "pid=($pids)," |
                   awk '{split($4, a, ":"); print a[length(a)]}' |
                   sort -u | tr '\n' ',' | sed 's/,$//')

    if [ -z "$process_ports" ]; then
        echo -e "${YELLOW}Process '$process_name' (PIDs: ${pids//|/, }) has no active TCP connections${NC}" >&2
        # debug
        echo -e "${YELLOW}Debug info:${NC}" >&2
        echo -e "${YELLOW}Ports to check: $ports_pattern${NC}" >&2
        echo -e "${YELLOW}PIDs found: $pids${NC}" >&2
        echo -e "${YELLOW}All connections for PIDs:${NC}" >&2
        echo "$ss_output" | grep -E "pid=($pids)," >&2 || echo "    (none)" >&2
        echo -e "${YELLOW}All connections for ports:${NC}" >&2
        echo "$ss_output" | grep -E ":($ports_pattern)" >&2 || echo "    (none)" >&2
        return 1
    fi

    if ! echo "$ss_output" | grep -qE ":($ports_pattern).*,pid=($pids)"; then
        echo -e "${YELLOW}Process '$process_name' (PIDs: ${pids//|/, }) has no connections on specified ports (${ports[*]})${NC}" >&2
        echo -e "${YELLOW}Active connection ports: ${process_ports}${NC}" >&2
        # # debug
        echo -e "${YELLOW}Debug info:${NC}" >&2
        echo -e "${YELLOW}Ports to check: $ports_pattern${NC}" >&2
        echo -e "${YELLOW}PIDs found: $pids${NC}" >&2
        echo -e "${YELLOW}All connections for PIDs:${NC}" >&2
        echo "$ss_output" | grep -E "pid=($pids)," >&2 || echo "    (none)" >&2
        echo -e "${YELLOW}All connections for ports:${NC}" >&2
        echo "$ss_output" | grep -E ":($ports_pattern)" >&2 || echo "    (none)" >&2
        return 1
    fi

    echo -e "${GREEN}Success: Process '$process_name' (PIDs: ${pids//|/, }) running as user '$user' has connections on ports: ${ports[*]}${NC}"
    echo -e "${GREEN}All active connection ports: ${process_ports}${NC}"
    return 0
}

# --- Main Execution ---
if [ -n "$run_as_user" ]; then
    # Check if user exists
    if ! id "$run_as_user" &>/dev/null; then
        echo -e "${RED}Error: User '$run_as_user' does not exist${NC}" >&2
        exit 1
    fi

    if check_ports_as_user "$run_as_user"; then
        exit 0
    else
        exit 1
    fi
else
    # Check all users running the process
    found=0
    declare -a checked_users=()

    while read -r user; do
        # Skip duplicate users using explicit loop comparison
        is_duplicate=0
        for checked_user in "${checked_users[@]}"; do
            if [ "$checked_user" = "$user" ]; then
                is_duplicate=1
                break
            fi
        done

        if [ $is_duplicate -eq 1 ]; then
            continue
        fi

        if check_ports_as_user "$user"; then
            found=1
            checked_users+=("$user")
        fi
    done < <(ps -eo user,comm | awk -v p="$process_name" '$2 == p {print $1}' | sort -u)

    if [ "$found" -eq 0 ]; then
        echo -e "${RED}Error: No instances of '$process_name' found with connections on specified ports${NC}" >&2
        exit 1
    fi
fi

exit 0