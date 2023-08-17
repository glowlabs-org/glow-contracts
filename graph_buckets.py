import matplotlib.pyplot as plt
import json 
import csv
with open('z_buckets.json') as f:
    data = json.load(f)
    #{id:number,amountInBucket:number}
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
    with open('buckets.csv', 'w', newline='') as csvfile:
        fieldnames = ['id', 'amountInBucket', 'inheritedFromLastWeek', 'amountToDeduct']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for i in range(len(ids)):
            writer.writerow({'id': ids[i], 'amountInBucket': amounts[i], 'inheritedFromLastWeek': inheritedFromLastWeeks[i], 'amountToDeduct': amountToDeduct[i]})

    # #plot the data
    # plt.bar(ids,amounts)
    # plt.xlabel('Bucket ID')
    # plt.ylabel('Amount in Bucket')
    # plt.title('Amount in each Bucket')
    # plt.show()