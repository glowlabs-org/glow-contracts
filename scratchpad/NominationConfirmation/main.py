import csv
import math
import random

def quote(amountAToAddInLP:int,reservesA:int,reservesB:int):
    return (amountAToAddInLP*reservesB)/reservesA

def calculate_univ2_lp(reservesA:int,reservesB:int,amountAToAddToLP:int,amountBToAddToLP:int,totalLP:int):
    a = (amountAToAddToLP*totalLP)/reservesA
    amountBToAddToLP = quote(amountAToAddToLP,reservesA,reservesB)
    b = (amountBToAddToLP*totalLP)/reservesB
    return min(a,b)

def glow_lp(reservesA:int,reservesB:int,amountAToAddToLP:int,amountBToAddToLP:int,totalLP:int):
    amountBToAddToLP = quote(amountAToAddToLP,reservesA,reservesB)
    return math.sqrt(amountAToAddToLP*amountBToAddToLP)
    
    
def find_diff():
    #find random values for reservesA, reservesB, amountAToAddToLP, amountBToAddToLP, totalLP
    reservesA = random.randint(1,1000000)
    reservesB = random.randint(1,1000000)
    amountAToAddToLP = random.randint(1,1000000)
    amountBToAddToLP = random.randint(1,1000000)
    totalLP = random.randint(1,1000000)

    univ2 = calculate_univ2_lp(reservesA,reservesB,amountAToAddToLP,amountBToAddToLP,totalLP)
    glow = glow_lp(reservesA,reservesB,amountAToAddToLP,amountBToAddToLP,totalLP)
    diff = abs(univ2-glow)
    return(univ2,glow,diff)


def main():
    rand_csv_name = "random.csv"
    lines = []
    for i in range(100000):
        univ2,glow,diff = find_diff()
        percent_diff = diff/univ2
        lines.append([univ2,glow,diff,percent_diff])
    with open(rand_csv_name, 'w') as writeFile:
        writer = csv.writer(writeFile)
        writer.writerows(lines)
        
main()