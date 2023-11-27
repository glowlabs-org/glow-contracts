import os
import json

path = "cloc_outputs"

try:
    files = os.listdir(path)
except FileNotFoundError:
    print(f"Directory '{path}' not found.")
    exit(1)

# Markdown table header
string_to_write = "| Contract | LOC | Comments |\n| --- | --- | --- |\n"
total_loc = 0
total_comments = 0

for file in files:
    if file.endswith(".json"):
        file_path = os.path.join(path, file)
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                loc = data["SUM"]["code"]
                comments = data["SUM"]["comment"]
                string_to_write += f"| {file.replace('json','sol')} | {loc} | {comments} |\n"
                total_loc += loc
                total_comments += comments
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Error processing file {file}: {e}")

# Add total count to the Markdown table
string_to_write += f"| Total | {total_loc} | {total_comments} |\n"

# Write to Markdown file
with open("cloc-table.md", "w") as f:
    f.write(string_to_write)
