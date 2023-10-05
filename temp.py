

def me(x):
    return .006 * 2 ** (x/100_000_000)



me_zero = me(0)
me_one = me(1)



def geometric_series_sum(a, r, n):
    """
    Calculate the sum of the first n terms of a geometric series with 
    initial term a and common ratio r.
    
    :param a: First term of the geometric series.
    :param r: Common ratio of the geometric series.
    :param n: Number of terms to sum.
    :return: Sum of the first n terms.
    """
    
    # If r is 1, handle it as a special case
    if r == 1:
        return n * a
    
    
    # Use the geometric series sum formula
    return (a * (1 - r**n)) / (1 - r)


a1 = .6
a2 = .006 
r1 = 1.000000693 
r2 = (me_one/me_zero)
n1 = 1_000_000
n2 = 1_000_000 * 100

res1 = geometric_series_sum(a1, r1, n1)
print(f"res1: {res1}")
res2 = geometric_series_sum(a2, r2, n2)
print(f"res2: {res2}")



def shift_left(x, n):
    """
    Shift the bits of x left by n places.
    
    :param x: Number to shift.
    :param n: Number of places to shift.
    :return: x shifted left by n places.
    """
    
    return x * (2 ** n)


def shift_right(x, n):
    """
    Shift the bits of x right by n places.
    
    :param x: Number to shift.
    :param n: Number of places to shift.
    :return: x shifted right by n places.
    """
    
    return x / (2 ** n)

r1_64x64 = shift_left(r1, 64)
r2_64x64 = shift_left(r2, 64)

r1_64x64_shr =  shift_right(r1_64x64, 64)
r2_64x64_shr =  shift_right(r2_64x64, 64)


print(format(r1_64x64, ".0f"))
print(format(r2_64x64, ".0f"))
print(format(r1_64x64_shr, ".0f"))
print(format(r2_64x64_shr, ".0f"))
# with open("data.txt","w") as f:
#     f.write(f"{r1_64x64}\n")
#     f.write(f"{r2_64x64}\n")

    
def float_to_64x64(floatNumber):
    MULTIPLIER = 2**64
    int128_representation = int(round(floatNumber * MULTIPLIER))
    return int128_representation

# Example usage:
floatNumber = 1.000000693
result = float_to_64x64(floatNumber)
print(result)

print(r2 * 10_000_000_000_000_00)

print(r2)

print(float_to_64x64(.0000000069314718))
print(float_to_64x64(6 * 1e3))