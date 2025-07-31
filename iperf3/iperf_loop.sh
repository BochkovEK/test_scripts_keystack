#!/bin/bash

# To start
#   nohup ./iperf_loop.sh 10.224.54.58:5201 >/dev/null 2>&1 &
# To check
#   ss -ntp
#   tail -f /tmp/iperf_client.log
# To stop
#   kill $(cat /tmp/iperf_client.pid)


# Configuration
LOG_FILE="/tmp/iperf_client.log"
TEST_DURATION=1
PAUSE_BETWEEN_TESTS=1
PID_FILE="/tmp/iperf_client.pid"
DEFAULT_PORT="5201"

# Initialize variables from arguments or environment
parse_input() {
    if echo "$1" | grep -q ":"; then
        SERVER_IP=$(echo "$1" | cut -d: -f1)
        SERVER_PORT=$(echo "$1" | cut -d: -f2)
    else
        SERVER_IP="$1"
        SERVER_PORT="$DEFAULT_PORT"
    fi
}

# Validate connection
check_connection() {
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/$SERVER_IP/$SERVER_PORT" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot connect to $SERVER_IP:$SERVER_PORT" | tee -a "$LOG_FILE"
        echo "Available network interfaces:" | tee -a "$LOG_FILE"
        ip -o addr show | awk '{print $2": "$4}' | tee -a "$LOG_FILE"
        return 1
    fi
    return 0
}

# Main execution
main() {
    # 1. Get server address
    if [ -n "$1" ]; then
        parse_input "$1"
    elif [ -n "$IPERF_SERVER" ]; then
        parse_input "$IPERF_SERVER"
    else
        echo "ERROR: No server specified!" | tee -a "$LOG_FILE"
        echo "Usage: $0 [IP:PORT] or set IPERF_SERVER env" | tee -a "$LOG_FILE"
        exit 1
    fi

    # 2. Validate input
    if [ -z "$SERVER_IP" ] || [ -z "$SERVER_PORT" ]; then
        echo "ERROR: Empty server address!" | tee -a "$LOG_FILE"
        exit 1
    fi

    # 3. Check connection
    if ! check_connection; then
        exit 1
    fi

    # 4. Main loop
    while true; do
        {
            echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
            iperf3 -c "$SERVER_IP" -p "$SERVER_PORT" -t "$TEST_DURATION" --connect-timeout 5000
            echo ""
        } | tee -a "$LOG_FILE"
        sleep "$PAUSE_BETWEEN_TESTS"
    done
}

# Startup procedure
{
    echo "=== Startup $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "PID: $$"
    echo "Args: $@"
    echo "Env IPERF_SERVER: $IPERF_SERVER"

    # Create PID file
    echo $$ > "$PID_FILE"
    trap "rm -f '$PID_FILE'" EXIT

    main "$@"
} >> "$LOG_FILE" 2>&1