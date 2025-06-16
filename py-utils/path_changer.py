import os

def is_text_file(file_path):
    """Check if a file is likely a text file by trying to read a small portion."""
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            file.read(1024)  # Try to read first 1024 bytes
        return True
    except (UnicodeDecodeError, PermissionError):
        return False

def replace_in_file(file_path, old_string, new_string):
    """Replace occurrences of old_string with new_string in the specified file."""
    # Skip if it's not a text file
    if not is_text_file(file_path):
        print(f"Skipping binary/non-text file: {file_path}")
        return
        
    with open(file_path, 'r', encoding='utf-8') as file:
        content = file.read()
    content = content.replace(old_string, new_string)
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)

def process_directory(directory, old_string, new_string):
    """Recursively process all files in the directory, replacing the specified string."""
    for root, _, files in os.walk(directory):
        for file_name in files:
            # Skip hidden files like .DS_Store
            if file_name.startswith('.'):
                continue
            file_path = os.path.join(root, file_name)
            replace_in_file(file_path, old_string, new_string)

# Set the directory and strings to be replaced
# src_directory = 'src'
# old_alias = '@/'
# new_alias = '@glow-v2/'

# # Execute the replacement
# process_directory(src_directory, old_alias, new_alias)


# src_directory = 'test'
# old_alias = '#/'
# new_alias = '#glow-v2-tests/'

# # Execute the replacement
# process_directory(src_directory, old_alias, new_alias)


src_directories = ['src',"test","script"]
old_aliases = ['@/',"@/","@/"]
new_aliases = ['@glow/',"@glow/","@glow/"]

for src_directory, old_alias, new_alias in zip(src_directories, old_aliases, new_aliases):
    process_directory(src_directory, old_alias, new_alias)
