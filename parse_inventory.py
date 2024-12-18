import sys
import os
import re

# the script work by inventory_to_hosts.sh

node_pattern = "-lcm-|-comp-|-cmpt-|-ctrl-|-net-"
lcm_pattern = "lcm-01"
kolla_internal_address = "kolla_internal_address"
external_floating = "external_floating"
ansible_host = "ansible_host"
path_to_inventory = sys.argv[1]
internal_prefix = os.environ['INT_PREF']
external_prefix = os.environ['EXT_PREF']
output_file = os.environ['OUTPUT_FILE']
region = os.environ['REGION']
domain = os.environ['DOMAIN']
hosts_string = []

# print(os.environ['DOMAIN'])
# print(os.environ['REGION'])
# print(os.environ['OUTPUT_FILE'])


def parse_inventory(path):
    inventory = open(path, "r")
    for line in inventory:
        print(line)
        words = line.split()
        for word in words:
            print(word)
            string = ""
            if ansible_host in word:
                ip = word.split('=')[1]
                string = f"{ip} {words[0]}"
                print(string)
            if kolla_internal_address in word:
                ip = word.split('=')[1]
                string = f"{ip} {internal_prefix}.{region}.{domain}"
                print(string)
            if external_floating in word:
                ip = word.split('=')[1]
                string = f"{ip} {external_prefix}.{region}.{domain}"
                print(string)
            if string and string not in hosts_string:
                hosts_string.append(string)


def write_file(path_to_file, strings):
    file = open(path_to_file, "w")
    file.write("# ------ ADD strings ------" + "\n")
    for line in strings:
        last_word = line.split()[-1]
        is_node_string = re.search(node_pattern, last_word)
        if is_node_string:
            is_lcm_node = re.search(lcm_pattern, last_word)
            if is_lcm_node:
                short_name = f"{last_word.split('-')[-2]}-{last_word.split('-')[-1]}"
                file.write(line + f" {short_name} lcm-nexus.{domain} netbox.{domain} gitlab.{domain} vault.{domain}\n")
            else:
                short_name = f"{last_word.split('-')[-2]}-{last_word.split('-')[-1]}"
                file.write(line + f" {short_name}\n")
        else:
            file.write(line + "\n")
    # file.write("\n")
    file.close()


parse_inventory(path_to_inventory)
write_file(output_file, hosts_string)

# parse_inventory(path_to_inventory)

# print(path_to_inventory)
#
# inventory = open(path_to_inventory, 'r')
#
# print(inventory)
#
# # inventory_lines = inventory.readlines()
# for line in inventory:
#     print(line)
#     # if ansible_host in line:
#     #     print(line)
#


# print("Data is written into the file.")
