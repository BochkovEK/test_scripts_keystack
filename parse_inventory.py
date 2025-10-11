import sys
import os
import re
import socket

# Script works with inventory_to_hosts.sh

node_pattern = "-lcm-|-comp-|-cmpt-|-ctrl-|-net-|-add_vm-"
lcm_pattern = "lcm-01"
kolla_internal_address = "kolla_internal_address"
external_floating = "external_floating"
ansible_host = "ansible_host"
path_to_inventory = sys.argv[1]
internal_prefix = os.environ['INT_PREF']
external_prefix = os.environ['EXT_PREF']
output_file = os.environ['OUTPUT_FILE_PATH']
region = os.environ['REGION']
domain = os.environ['DOMAIN']
gitlab_short_name = os.environ['GITLAB_SHORT_NAME']
hosts_string = []

# Dictionary to store hosts by groups
hosts_by_group = {
    'control': [],
    'network': [],
    'compute': [],
    'other': []
}

# Dictionary for group to prefix mapping
group_prefixes = {
    'control': 'ctrl',
    'network': 'net',
    'compute': 'comp'
}


def resolve_dns(hostname):
    """DNS resolution to get IP address using socket"""
    try:
        ip = socket.gethostbyname(hostname)
        print(f"DNS resolved {hostname} -> {ip}")
        return ip
    except socket.gaierror as e:
        print(f"DNS resolution failed for {hostname}: {e}")
        return None
    except Exception as e:
        print(f"Unexpected error resolving {hostname}: {e}")
        return None


def parse_inventory(path):
    """Parse inventory file and extract hosts with their IP addresses"""
    current_group = None

    with open(path, "r") as inventory:
        for line in inventory:
            line = line.strip()

            # Skip empty lines and comments
            if not line or line.startswith('#'):
                continue

            # Detect current group section
            if line.startswith('[') and line.endswith(']'):
                group_name = line[1:-1].split(':')[0]  # Remove [ ] and possible :vars
                if group_name in hosts_by_group:
                    current_group = group_name
                else:
                    current_group = 'other'
                continue

            # Process host lines in known groups
            if current_group and current_group in hosts_by_group and line:
                # Extract hostname (first word in line)
                hostname = line.split()[0].strip()
                if hostname and hostname not in hosts_by_group[current_group]:
                    hosts_by_group[current_group].append(hostname)

            # Process variables with IP addresses (only for non-group entries)
            words = line.split()
            for word in words:
                string = ""
                if ansible_host in word:
                    ip = word.split('=')[1]
                    string = f"{ip} {words[0]}"
                    print(f"Found ansible_host entry: {string}")
                if kolla_internal_address in word:
                    ip = word.split('=')[1]
                    string = f"{ip} {internal_prefix}.{region}.{domain}"
                    print(f"Found kolla internal: {string}")
                if external_floating in word:
                    ip = word.split('=')[1]
                    string = f"{ip} {external_prefix}.{region}.{domain} backend.{external_prefix}.{region}.{domain}"
                    print(f"Found external floating: {string}")
                if string and string not in hosts_string:
                    hosts_string.append(string)


def get_ip_for_host(hostname, inventory_path):
    """Get IP address from inventory file or via DNS resolution"""
    # First check if hostname already exists in hosts_string (from variable parsing)
    for entry in hosts_string:
        if hostname in entry:
            ip = entry.split()[0]
            print(f"Found existing IP for {hostname}: {ip}")
            return ip

    # If not found in hosts_string, try to extract from inventory
    ip_from_inventory = None

    try:
        with open(inventory_path, "r") as inventory:
            for line in inventory:
                line = line.strip()
                if hostname in line and ansible_host in line:
                    # Look for ansible_host variable with our host
                    parts = line.split()
                    for part in parts:
                        if part.startswith(ansible_host + '='):
                            ip_from_inventory = part.split('=')[1]
                            print(f"Found IP in inventory: {hostname} -> {ip_from_inventory}")
                            return ip_from_inventory
    except Exception as e:
        print(f"Error reading inventory: {e}")

    # If no IP in inventory, try DNS resolution
    if not ip_from_inventory:
        ip_from_dns = resolve_dns(hostname)
        if ip_from_dns:
            return ip_from_dns

    return None


def generate_host_entries():
    """Generate host entries for output file"""
    entries = []
    unresolved_hosts = []

    for group, hosts in hosts_by_group.items():
        if group == 'other':
            continue

        prefix = group_prefixes.get(group, group)

        for hostname in hosts:
            ip = get_ip_for_host(hostname, path_to_inventory)
            if ip:
                # Extract number from hostname (assuming name-XX.domain.com format)
                host_number_match = re.search(r'(\d+)', hostname)
                if host_number_match:
                    host_number = host_number_match.group(1)
                    short_name = f"{prefix}-{host_number}"
                    entry = f"{ip} {hostname} {short_name}"
                    entries.append(entry)
                else:
                    # Alternative if different hostname format
                    short_name = f"{prefix}-{hostname.split('.')[0].replace('domain_name-', '')}"
                    entry = f"{ip} {hostname} {short_name}"
                    entries.append(entry)
            else:
                unresolved_hosts.append(hostname)

    if unresolved_hosts:
        print(f"Warning: Could not resolve IP for hosts: {unresolved_hosts}")

    return entries


def is_network_subset_of_control():
    """Check if network group hosts are a subset of control group hosts"""
    network_hosts = set(hosts_by_group.get('network', []))
    control_hosts = set(hosts_by_group.get('control', []))

    # Если network пустой или полностью содержится в control
    return not network_hosts or network_hosts.issubset(control_hosts)


def write_file(path_to_file, strings):
    """Write host entries to output file with simplified hostnames"""
    with open(path_to_file, "w") as file:
        # First write group-based entries
        control_entries = [s for s in strings if 'ctrl-' in s]
        network_entries = [s for s in strings if 'net-' in s]
        compute_entries = [s for s in strings if 'comp-' in s]
        lcm_entries = [s for s in strings if 'lcm-' in s]
        other_entries = [s for s in strings if not any(x in s for x in ['ctrl-', 'net-', 'comp-', 'lcm-'])]

        # Check if network group is a subset of control group
        network_subset_of_control = is_network_subset_of_control()

        if network_subset_of_control and network_entries:
            print("Network group hosts are subset of control group - skipping network section")
        elif network_entries:
            print("Network group has unique hosts - including network section")

        # Write group entries with separation
        if control_entries:
            file.write("# Control nodes\n")
            for entry in control_entries:
                file.write(entry + "\n")
            file.write("\n")

        # Only write network section if it has unique hosts (not subset of control)
        if network_entries and not network_subset_of_control:
            file.write("# Network nodes\n")
            for entry in network_entries:
                file.write(entry + "\n")
            file.write("\n")

        if compute_entries:
            file.write("# Compute nodes\n")
            for entry in compute_entries:
                file.write(entry + "\n")
            file.write("\n")

        if lcm_entries:
            file.write("# LCM nodes\n")
            for entry in lcm_entries:
                file.write(entry + "\n")
            file.write("\n")

        # Then write variable-based entries (only non-duplicates)
        file.write("# Additional entries from variables\n")
        written_ips = set()

        # Track IPs from group entries to avoid duplicates
        for entry in strings:
            ip = entry.split()[0]
            written_ips.add(ip)

        for line in hosts_string:
            line_ip = line.split()[0]

            # Skip entries that are already in group-based output
            if line_ip in written_ips:
                print(f"Skipping duplicate entry: {line}")
                continue

            last_word = line.split()[-1]
            is_node_string = re.search(node_pattern, last_word)

            if is_node_string:
                is_lcm_node = re.search(lcm_pattern, last_word)
                if is_lcm_node:
                    # Extract simple hostname for LCM node and add service names
                    short_name = f"{last_word.split('-')[-2]}-{last_word.split('-')[-1]}"
                    file.write(
                        line + f" {short_name} lcm-nexus.{region}.{domain} netbox.{region}.{domain} {gitlab_short_name}.{region}.{domain} vault.{region}.{domain}\n")
                else:
                    # Extract simple hostname for other nodes
                    short_name = f"{last_word.split('-')[-2]}-{last_word.split('-')[-1]}"
                    file.write(line + f" {short_name}\n")
            else:
                file.write(line + "\n")

            written_ips.add(line_ip)


# Main execution logic
if __name__ == "__main__":
    try:
        parse_inventory(path_to_inventory)
        print(f"Parsed groups: {[k for k, v in hosts_by_group.items() if v]}")
        print(f"Found variable entries: {len(hosts_string)}")

        host_entries = generate_host_entries()
        write_file(output_file, host_entries)

        print(f"Generated {len(host_entries)} host entries")
        print(f"Data written to {output_file}")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)