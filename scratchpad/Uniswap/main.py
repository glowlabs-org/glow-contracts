
import math


reserve_gcc = 100 * 1e18
reserve_usdc = 2000 * 1e6

# 1 gcc = 20 usdc

# #First swap 10 gcc for us

#I want to swap 20

def vorick(amount_to_retire,amount_in_reserves):
    return math.sqrt(amount_in_reserves*(amount_to_retire + amount_in_reserves)) - amount_in_reserves


print(vorick(20*1e18,reserve_gcc))