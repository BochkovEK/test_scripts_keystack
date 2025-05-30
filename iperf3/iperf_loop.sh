#!/bin/bash

# To start
#   nohup ./iperf_loop.sh 192.168.1.100:5201 >> /tmp/iperf_client.log 2>&1 &
# To check
#   ss -ntp
#   tail -f /tmp/iperf_client.log
# To stop
#   kill $(cat /tmp/iperf_client.pid)

# Continuous iperf3 client test script
# Features:
# - Infinite loop with configurable test duration and pauses
# - Logging to /tmp/iperf_client.log
# - PID file for process management
# - Port connectivity check
# - Flexible server address input (args or env vars)

### Configuration ###
SERVER_IP=""          # Can be set via env or arguments
SERVER_PORT=""        # Can be set via env or arguments
LOG_FILE="/tmp/iperf_client.log"
TEST_DURATION=1       # Duration of each test in seconds
PAUSE_BETWEEN_TESTS=1 # Pause between tests in seconds
PID_FILE="/tmp/iperf_client.pid"
DEFAULT_PORT="5201"   # Default iperf3 server port

### Functions ###

# Check if port is reachable
check_port() {
  local ip=$1
  local port=$2
  timeout 1 bash -c "cat < /dev/null > /dev/tcp/${ip}/${port}" 2>/dev/null
  return $?
}

# Parse IP:PORT format
parse_input() {
    if echo "$1" | grep -q ":"; then
        SERVER_IP=$(echo "$1" | cut -d: -f1)
        SERVER_PORT=$(echo "$1" | cut -d: -f2)
    else
        SERVER_IP="$1"
        SERVER_PORT="$DEFAULT_PORT"
    fi
}

### Main ###

# Create PID file and set cleanup trap
echo $$ > "$PID_FILE"
trap "rm -f '$PID_FILE'" EXIT

# Get server address (priority: arguments > environment variables)
if [ -n "$1" ]; then
  parse_input "$1"
elif [ -n "$IPERF_SERVER" ]; then
  parse_input "$IPERF_SERVER"
fi

# Validate required parameters
if [ -z "$SERVER_IP" ] || [ -z "$SERVER_PORT" ]; then
  echo "ERROR: Server address not specified!" | tee -a "$LOG_FILE"
  echo "Usage: $0 [IP:PORT]" | tee -a "$LOG_FILE"
  echo "Or set IPERF_SERVER environment variable" | tee -a "$LOG_FILE"
  exit 1
fi

# Verify server connectivity
if ! check_port "$SERVER_IP" "$SERVER_PORT"; then
  echo "ERROR: Cannot connect to $SERVER_IP:$SERVER_PORT!" | tee -a "$LOG_FILE"
  exit 1
fi

# Log header
echo "=== iperf3 continuous test started $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$LOG_FILE"
echo "Server: $SERVER_IP:$SERVER_PORT" | tee -a "$LOG_FILE"
echo "Test duration: ${TEST_DURATION}s, Pause: ${PAUSE_BETWEEN_TESTS}s" | tee -a "$LOG_FILE"

# Main test loop
while true; do
  TIMESTAMP=$(date '+%H:%M:%S')
  {
    echo "--- $TIMESTAMP ---"
    iperf3 -c "$SERVER_IP" -p "$SERVER_PORT" -t "$TEST_DURATION" --title "$TIMESTAMP - Test"
    echo ""
  } | tee -a "$LOG_FILE"
  sleep "$PAUSE_BETWEEN_TESTS"
done