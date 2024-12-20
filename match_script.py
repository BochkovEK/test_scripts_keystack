import sys

text_file_path = sys.argv[1]
to_find_file_path = sys.argv[2]

# text_file_path = "./text.txt"

# to_find_file_path = "./to_find.txt"
match_file_path = "./match.txt"
match = []

with open(text_file_path) as text_file:
    text_lines = [line.rstrip() for line in text_file]

with open(to_find_file_path) as to_find_file:
    to_find_lines = [line.rstrip() for line in to_find_file]

for find in to_find_lines:
    print(find)
    for text_line in text_lines:
        print(text_line)
        if find in text_line:
            match.append(text_line)
            break

# Set the mode in open() to "a" (append) instead of "w" (write):
for line in match:
    print(line)
    # with open(match_file_path, "a") as f:
    #     f.write(line+"\n")

