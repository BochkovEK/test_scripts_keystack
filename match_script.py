import sys
import os

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
else:
    for find in find_lines:
        if debug:
            print(find)
        for where_find_line in where_find_lines:
            if debug:
                print(where_find_line)
            if find not in where_find_line:
                match.append(where_find_line)
                break


# Set the mode in open() to "a" (append) instead of "w" (write):
for line in match:
    if debug:
        print(line)
    with open(match_file_path, "a") as f:
        f.write(line+"\n")

