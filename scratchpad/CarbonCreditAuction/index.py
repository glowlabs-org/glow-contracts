def min(x,y):
    if x<y:
        return x
    return y

def max(x,y):
    if x > y:
        return x
    return y


"""
Thoughts/Playground
"""
vesting_length = 1 # 1 week
# vesting_length_seconds = vesting_length * 7 * 24 * 60 * 60


first_amount_added = 1200
slope = first_amount_added / vesting_length
time_passed_when_second_amount_gets_added = .5
total_that_should_be_available_from_first_amount = time_passed_when_second_amount_gets_added * first_amount_added
amount_left_to_sell_from_first_amount = first_amount_added - total_that_should_be_available_from_first_amount
second_amount_added = 300

total_now_available_for_sale = second_amount_added + amount_left_to_sell_from_first_amount

print(f"amount left = {total_now_available_for_sale}")
#New Slope
#If we had just kept first amount, 1200, 1200 would have vested at t1
#now at t1 we'll have

#600 + (900 * .5) = 1050

#Let's try the accelerator method
#In accelerator method, we always have two slopes and an accelerator

a1 = 1200
time_passed = .5
a1_slope = a1 / vesting_length
amt_avail_a1 = time_passed * time_passed
amt_left_a1 = a1 - amt_avail_a1
time_left_in_a1 = vesting_length - time_passed #.5
a2 = 300
a2_slope = a2 / vesting_length

# #So, we need the 600 to vest in .5 time from a1
#a1 slope stays the same, but we define a max amount, so
# min(amt_left_a1, a1_slope / t) + min(amt_left,a2_slope / t)

#Then we add an a3
#a3 gets merged with a1?
print(f"a1 slope = {a1_slope}")