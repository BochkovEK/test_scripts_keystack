#!/bin/bash

# Colors
normal=$(tput sgr0)
cyan=$(tput setaf 6)
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
#yellow=$(tput setaf 3)

# Function to show usage
usage() {
    echo "Usage: $0 \"<start_ip> <end_ip>\""
    echo "Example: $0 \"10.224.140.97 10.224.140.126\""
    exit 1
}

# Check if argument is provided
if [ $# -ne 1 ]; then
    echo -e "${red}Error: Missing required argument${normal}"
    usage
fi

# Ask for SSH tunnel connection
echo -e "${blue}Please provide SSH tunnel connection in format user@ip:${normal}"
read -r SSH_TUNNEL

# Validate SSH tunnel format
if ! echo "$SSH_TUNNEL" | grep -qE '^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$'; then
    echo -e "${red}Error: Invalid SSH tunnel format. Use user@ip${normal}"
    exit 1
fi

# Extract user and IP from SSH tunnel
SSH_USER=$(echo "$SSH_TUNNEL" | cut -d@ -f1)
SSH_IP=$(echo "$SSH_TUNNEL" | cut -d@ -f2)

echo -e "${cyan}Using SSH tunnel: $SSH_TUNNEL${normal}"
echo ""

# Parse the input argument
IP_RANGE=$1

# Split the input into start and end IPs
START_IP=$(echo "$IP_RANGE" | awk '{print $1}')
END_IP=$(echo "$IP_RANGE" | awk '{print $2}')

# Validate IP addresses
if ! echo "$START_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || \
   ! echo "$END_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo -e "${red}Error: Invalid IP format${normal}"
    usage
fi

# Extract network part and host parts
NETWORK_PART=$(echo "$START_IP" | cut -d. -f1-3)
START_HOST=$(echo "$START_IP" | cut -d. -f4)
END_HOST=$(echo "$END_IP" | cut -d. -f4)

# Validate that both IPs are in the same network
if [ "$NETWORK_PART" != "$(echo "$END_IP" | cut -d. -f1-3)" ]; then
    echo -e "${red}Error: IP addresses must be in the same network${normal}"
    usage
fi

# Validate host ranges
if [ "$START_HOST" -gt "$END_HOST" ]; then
    echo -e "${red}Error: Start IP must be less than or equal to End IP${normal}"
    usage
fi

echo -e "Pinging IP range through SSH tunnel $SSH_TUNNEL:"
echo -e "${cyan}From: $START_IP to $END_IP${normal}"
echo ""

i=$START_HOST
while [[ $i -le $END_HOST ]]; do
    IP="$NETWORK_PART.$i"
    echo "Testing $IP through SSH tunnel..."

    # Ping through SSH tunnel
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_TUNNEL" "ping -c 2 -W 1 $IP" &> /dev/null; then
        printf "%40s\n" "${green}There is a connection with $IP - success${normal}"
    else
        printf "%40s\n" "${red}No connection with $IP - error!${normal}"
    fi
    ((i = i + 1))
done

echo ""
echo -e "${green}Scan completed through SSH tunnel $SSH_TUNNEL!${normal}"