#!/bin/bash

# Script to get node list from hosts file and return string like: "node_name1:ip1 node_name2:ip2 ... node_nameN:ipN"
# Requires node IPs and names to be defined in /etc/hosts

default_hosts_path="/etc/hosts"

# Node name patterns
comp_pattern="comp\-..(\s|$)"
ctrl_pattern="ctrl\-..(\s|$)"
net_pattern="net\-..(\s|$)"

# Colors
red=$(tput setaf 1)
normal=$(tput sgr0)

# Default values
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $TS_HOSTS_PATH ]] && TS_HOSTS_PATH="$default_hosts_path"
[[ -z $RETURN_TYPE_NODE_NAME ]] && RETURN_TYPE_NODE_NAME=""

# Parameter counter
count=1

# Function to define parameters from positional arguments
define_parameters() {
  [ "$count" = 1 ] && [[ -n $1 ]] && {
    NODES_TYPE="$1"
    [ "$TS_DEBUG" = true ] && echo -e "Nodes type parameter found with value $NODES_TYPE"
  }
}

# Parse command line arguments
while [ -n "$1" ]; do
  case "$1" in
    --help)
      echo -E "
      Usage: $0 [OPTIONS]

      Node IPs and names must be defined in hosts file (default: $default_hosts_path)

      Options:
        -nt, -type_of_nodes <type>    Node type: 'ctrl', 'comp', 'net', 'all'
        -nn, -nodes_name <names>      Specific node names (space-separated)
        -h, -hosts_path <path>        Path to hosts file
        -return_type <node_name>      Return type of specified node
        -debug                        Enable debug mode
        --help                        Show this help message
      "
      exit 0
      ;;

    -debug)
      TS_DEBUG="true"
      [ "$TS_DEBUG" = true ] && echo -e "Debug mode enabled"
      ;;

    -nt|-type_of_nodes)
      NODES_TYPE="$2"
      [ "$TS_DEBUG" = true ] && echo -e "Node type set to: $NODES_TYPE"
      shift
      ;;

    -nn|-nodes_name)
      NODES_NAME="$2"
      [ "$TS_DEBUG" = true ] && echo -e "Node names set to: $NODES_NAME"
      shift
      ;;

    -return_type)
      RETURN_TYPE_NODE_NAME="$2"
      [ "$TS_DEBUG" = true ] && echo -e "Return type for node: $RETURN_TYPE_NODE_NAME"
      shift
      ;;

    -h|-hosts_path)
      TS_HOSTS_PATH="$2"
      [ "$TS_DEBUG" = true ] && echo -e "Hosts file path set to: $TS_HOSTS_PATH"
      shift
      ;;

    --)
      shift
      break
      ;;

    *)
      [ "$TS_DEBUG" = true ] && echo -e "Parameter #$count: $1"
      define_parameters "$1"
      count=$((count + 1))
      ;;
  esac
  shift
done

# Function to find IP address in hosts file
find_in_hosts_file() {
    local hostname="$1"
    [ -f "$TS_HOSTS_PATH" ] || {
        echo "Hosts file $TS_HOSTS_PATH does not exist" >&2
        return 1
    }
    grep -w "$hostname" "$TS_HOSTS_PATH" | awk '{print $1}' | head -n1
}

# Function to resolve hostnames to IP addresses
resolve_hostname_to_ips() {
    local resolved_nodes=()

    for host in "${NODES[@]}"; do
        local ip
        ip=$(find_in_hosts_file "$host")

        if [ -n "$ip" ]; then
            resolved_nodes+=("$host:$ip")
        else
            echo "Warning: failed to resolve $host" >&2
            resolved_nodes+=("unresolved:$host")
        fi
    done

    echo "${resolved_nodes[*]}"
}

# Function to parse hosts file and extract nodes
parse_hosts() {
    [ "$TS_DEBUG" = true ] && echo "Parsing $TS_HOSTS_PATH for pattern: $nodes_to_find"

    # Populate NODES array from hosts file
    if [ ${#NODES[@]} -eq 0 ]; then
        while read -r line; do
            NODES+=("$line")
        done < <(grep -E "$nodes_to_find" "$TS_HOSTS_PATH" | awk '{print $2}')
    fi

    [ "$TS_DEBUG" = true ] && printf "Found nodes: %s\n" "${NODES[*]}"

    # Resolve hostnames to IPs
    resolve_hostname_to_ips

    # Validate we found nodes
    if [ ${#NODES[@]} -eq 0 ]; then
        echo "Failed to find nodes in $TS_HOSTS_PATH" >&2
        exit 1
    fi
}

# Function to determine node type based on pattern
define_node_type() {
    local node_type="$1"

    case "$node_type" in
        ctrl)
            nodes_to_find="$ctrl_pattern"
            [ "$TS_DEBUG" = true ] && echo -e "Looking for controller nodes"
            parse_hosts
            ;;

        comp|cmpt)
            nodes_to_find="$comp_pattern"
            [ "$TS_DEBUG" = true ] && echo -e "Looking for compute nodes"
            parse_hosts
            ;;

        net)
            nodes_to_find="$net_pattern"
            [ "$TS_DEBUG" = true ] && echo -e "Looking for network nodes"
            parse_hosts
            ;;

        all)
            nodes_to_find="$comp_pattern|$ctrl_pattern|$net_pattern"
            [ "$TS_DEBUG" = true ] && echo -e "Looking for all node types"
            parse_hosts
            ;;

        *)
            echo "${red}Unknown node type '$node_type'. Use: ctrl, comp, net, or all${normal}" >&2
            exit 1
            ;;
    esac
}

# Function to return type of specific node
return_type() {
    [ "$TS_DEBUG" = true ] && echo -e "Determining type for node: $RETURN_TYPE_NODE_NAME"

    local node_info
    node_info=$(grep -i "$RETURN_TYPE_NODE_NAME" "$TS_HOSTS_PATH" 2>/dev/null)

    [ "$TS_DEBUG" = true ] && echo -e "Node info found: $node_info"

    case "$node_info" in
        *ctrl*)
            echo "ctrl"
            ;;
        *comp*)
            echo "comp"
            ;;
        *net*)
            echo "net"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Main execution flow

# If return_type is requested, execute and exit
if [ -n "$RETURN_TYPE_NODE_NAME" ]; then
    return_type
    exit 0
fi

# If specific node names are provided, resolve them
if [ -n "$NODES_NAME" ]; then
    [ "$TS_DEBUG" = true ] && echo -e "Processing specific node names: $NODES_NAME"

    # Convert space-separated string to array
    IFS=' ' read -ra NODES <<< "$NODES_NAME"
    resolve_hostname_to_ips
    exit 0
fi

# Process nodes by type
define_node_type "$NODES_TYPE"