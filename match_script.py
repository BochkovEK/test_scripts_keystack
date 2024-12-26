import sys
import os

# To start
#   python3 ~/test_scripts_keystack/match_script.py ~/fail.list ~/all_tempest.list

# small file
what_find = sys.argv[1]
# big file
where_find = sys.argv[2]
match_file_path = "./match.txt"
debug = False
white_list = True
match = []

try:
    os.environ['WHITE_LIST']
except KeyError:
    pass
else:
    if os.environ['WHITE_LIST'] == "true":
        white_list = True
    else:
        white_list = False

try:
    os.environ['TS_DEBUG']
except KeyError:
    pass
else:
    if os.environ['TS_DEBUG'] == "true":
        debug = True

try:
    os.environ['OUTPUT_MATCH_FILE']
except KeyError:
    pass
else:
    if os.environ['OUTPUT_MATCH_FILE']:
        match_file_path = os.environ['OUTPUT_MATCH_FILE']

try:
    sys.argv[3]
except IndexError:
    pass
else:
    if sys.argv[3]:
        match_file_path = sys.argv[3]

with open(what_find) as what_find_file:
    find_lines = [line.rstrip() for line in what_find_file]

with open(where_find) as where_find_file:
    where_find_lines = [line.rstrip() for line in where_find_file]

if white_list:
    for find in find_lines:
        if debug:
            print(find)
        for where_find_line in where_find_lines:
            if debug:
                print(where_find_line)
            if find in where_find_line:
                match.append(where_find_line)
                break
else:  # black list
    for where_find_line in where_find_lines:
        print(where_find_line)
        not_in_list = True
        for find in find_lines:
            if debug:
                print(find)
            if find in where_find_line:
                not_in_list = False
                break
        if not_in_list:
            match.append(where_find_line + ":")


# Set the mode in open() to "a" (append) instead of "w" (write):
for line in match:
    if debug:
        print(line)
    with open(match_file_path, "a") as f:
        f.write(line+"\n")

