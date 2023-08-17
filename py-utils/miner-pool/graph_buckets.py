import matplotlib.pyplot as plt
import json 
import csv
import sys
from constants import BUCKETS_FILE_NAME

bucket_path = f"./py-utils/miner-pool/data/{BUCKETS_FILE_NAME}"
#revert and exit
def revert(message:str):
    raise Exception(message)
# revert("Error In Buckets")
with open(bucket_path) as f:
    data = json.load(f)
    
    ids = []
    amounts = []
    inheritedFromLastWeeks = []
    amountToDeduct = []
    for i in data:
        ids.append(i['id'])
        amounts.append(i['amountInBucket'])
        inheritedFromLastWeeks.append(i['inheritedFromLastWeek'])
        amountToDeduct.append(i['amountToDeduct'])

    #write it to a csv 
    with open('./py-utils/miner-pool/data/buckets.csv', 'w', newline='') as csvfile:
        fieldnames = ['id', 'amountInBucket', 'inheritedFromLastWeek', 'amountToDeduct']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for i in range(len(ids)):
            writer.writerow({'id': ids[i], 'amountInBucket': amounts[i], 'inheritedFromLastWeek': inheritedFromLastWeeks[i], 'amountToDeduct': amountToDeduct[i]})

    #plot the data
    plt.bar(ids,amounts)
    plt.xlabel('Bucket ID')
    plt.ylabel('Amount in Bucket')
    plt.title('Amount in each Bucket')
    plt.show()