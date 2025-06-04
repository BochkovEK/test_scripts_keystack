#!/bin/bash

# Example usage: bash ./nuttcp_logger.sh 10.224.54.80 -u -i1 -T10 -R 25m -f-drops

#-u    UDP protocol
#-R    Rate limit (m|M)bps
#-T 10 Test duration (seconds)
#-i 1  Interval (seconds between reports)

default_log_file="nuttcp_$(date '+%Y-%m-%d').log"
[[ -z $LOG_FILE ]] && LOG_FILE=$default_log_file

# Validate IP address format
#function validate_ip() {
#    local ip=$1
#    local stat=1
#
#    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
#        IFS='.' read -r -a octets <<< "$ip"
#        [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && \
#           ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]
#        stat=$?
#    fi
#    return $stat
#}

function validate_ip() {
    grep -E -q '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' <<< "$1"
}

# Check for server IP argument
if [ -z "$1" ]; then
    echo "Error: Server IP not specified" >&2
    echo "Usage: $0 <server_ip> [additional_nuttcp_parameters]" >&2
    exit 1
fi

SERVER="$1"

# Validate IP format
if ! validate_ip "$SERVER"; then
    echo "Error: Invalid IP address format" >&2
    exit 1
fi

shift  # Remove first argument (IP), pass remaining to nuttcp

# Write test header
echo "===== Test started at $(date) - Server: $SERVER =====" >> "$LOG_FILE"

# Run nuttcp with parameters and log output
nuttcp "$@" "$SERVER" | while read -r line; do
    echo "$(date '+%H:%M:%S') $line" >> "$LOG_FILE"
done

# Write test footer
echo "===== Test completed at $(date) - Server: $SERVER =====" >> "$LOG_FILE"