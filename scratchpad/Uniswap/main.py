
import math


# 1 gcc = 20 usdc

# #First swap 10 gcc for us

#I want to swap 20

def vorick(amount_to_retire,total_reserves):
    a = math.sqrt(total_reserves)
    b = math.sqrt(3988000 * amount_to_retire + 3988009 * total_reserves)
    c = 1997 * total_reserves
    d = 1994
    # print("a = ",a)
    # print("b = ",b)
    # print("c = ",c)
    # print()
    res = ((a*b)-c) / d
    return (a,b,c,d,a*b,res)
magnifier = 1e18
amount =  10000001 * magnifier
reserves = 33616776044342304721799538359722 * magnifier


(p_a,p_b,p_c,p_d,p_ab,res) = vorick(amount,reserves)

print("p_a = ",p_a)
print("p_b = ",p_b)
print("p_c = ",p_c)
print("p_ab = " + str(p_ab))


python_output = ((p_a*p_b)-p_c) / 1994
python_output = 8822560704.320963

print("amount = ",amount)
print("res = ",res)
# print(amount > res)
# p_a =  5797997589197697e+24
# p_b =  1.15786011856278e+28
# p_c =  6.713270176055159e+52
# p_ab = 6.713270176055159e+52


