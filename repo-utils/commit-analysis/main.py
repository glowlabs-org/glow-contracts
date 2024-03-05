import csv

#Read in  ./swap-successes.csv

file = open('swap-succeses.csv', 'r')
reader = csv.reader(file)
swap_successes = list(reader)

#totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves

error_threshold = 0.0001
for row in swap_successes:
    (totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves) = row
    #Find leftover GCC / amount
    leftoverGCC = float(leftoverGCC)
    amount = float(amount)
    leftoverGCCOverAmount = leftoverGCC / amount
    #Make sure that leftoverGCCOverAmount is less than 0.001
    if leftoverGCCOverAmount < error_threshold:
        continue
    else:
        amountDivTotalReserves = amount / float(totalReserves)
        if amountDivTotalReserves <= 15:
            print(f"Amount {amount}")
            print(f"Failure: {leftoverGCCOverAmount}")
            raise Exception("Failure")



#do the same for swap-succeses-usdc
file = open('swap-succeses-usdc.csv', 'r')
reader = csv.reader(file)
swap_successes = list(reader)

#totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves

for row in swap_successes:
    (totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves) = row
    #Find leftover GCC / amount
    leftoverUSDC = float(leftoverUSDC)
    amount = float(amount)
    leftoverUSDCOverAmount = leftoverUSDC / amount
    #Make sure that leftoverGCCOverAmount is less than 0.001
    if leftoverUSDCOverAmount < error_threshold:
        continue
    else:
        amountDivTotalReserves = amount / float(totalReserves)
        if amountDivTotalReserves <= 15:
            print(f"Amount {amount}")
            print(f"Failure: {leftoverUSDCOverAmount}")
            raise Exception("Failure")
        
print("Success")