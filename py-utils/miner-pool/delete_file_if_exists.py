#create a script that deletes a file if it exists

import os
from constants import BUCKETS_FILE_NAME

bucket_path = f"./py-utils/miner-pool/data/{BUCKETS_FILE_NAME}"
def delete_file_if_exists(file_name:str):
    if os.path.exists(file_name):
        os.remove(file_name)
    else:
        print("The file does not exist")

delete_file_if_exists(bucket_path)