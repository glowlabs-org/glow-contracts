starting_price = .003
decimals = 6

starting_price = starting_price * (10**decimals)

# Convert to integer after the calculation
starting_price = int(starting_price * (2**64))

def print_whole_number(number):
    # Using format to convert number to a string without scientific notation
    print("{:}".format(number))

# Example usage
print_whole_number(starting_price)