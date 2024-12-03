import sys

ansible_host = "ansible_host"
path_to_inventory = sys.argv[1]
output_file = "hosts_add_strings"
hosts_string = []


def parse_inventory(path):
    inventory = open(path, "r")
    for line in inventory:
        print(line)
        words = line.split()
        for word in words:
            print(word)
            if ansible_host in word:
                ip = word.split('=')[1]
                string = f"{ip} {words[0]}"
                print(string)
                if string not in hosts_string:
                    hosts_string.append(string)


def write_file(path_to_file, strings):
    file = open(path_to_file, "w")
    file.write("# ------ ADD strings ------" + "\n")
    for line in strings:
        last_word = line.split()[-1]
        short_name = f"{last_word.split('-')[-2]}-{last_word.split('-')[-1]}"
        file.write(line + f" {short_name}" + "\n")
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
