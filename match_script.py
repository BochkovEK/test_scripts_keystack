import sys

# small file
what_find = sys.argv[1]
# big file
where_find = sys.argv[2]

# text_file_path = "./text.txt"

# to_find_file_path = "./to_find.txt"
match_file_path = "./match.txt"
match = []

with open(what_find) as what_find_file:
    find_lines = [line.rstrip() for line in what_find_file]

with open(where_find) as where_find_file:
    where_find_lines = [line.rstrip() for line in where_find_file]

for find in find_lines:
    print(find)
    for where_find_line in where_find_lines:
        print(where_find_line)
        if find in where_find_line:
            match.append(where_find_line)
            break

# Set the mode in open() to "a" (append) instead of "w" (write):
for line in match:
    print(line)
    # with open(match_file_path, "a") as f:
    #     f.write(line+"\n")

