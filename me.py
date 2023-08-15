#natural log
import math

#ln(2)



def find_total_price(total_sold,tokens_to_buy):
    total_price = (.06 * 2** ((total_sold + tokens_to_buy)/1_000_000))/ 0.6931471805599453 - (.06 * 2** (total_sold/1_000_000))/ 0.6931471805599453
    return total_price


def manual_way(total_sold,tokens_to_buy):
    total_price = 0
    for i in range(total_sold,total_sold + tokens_to_buy):
        total_price += .06 * 2** (i/1_000_000)
    return total_price


print(find_total_price(0,12_000_000))
print(find_total_price(0,20))



print(manual_way(0,20))

print(manual_way(0,12_000_000))