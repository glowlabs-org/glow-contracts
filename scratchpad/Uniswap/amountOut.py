
reserveA = 400000000000000000000
reserveB = 100000000010000000001000000000


fee = 3 # 0.3%
def getAmountOut(amountIn,reserveIn,reserveOut):
    amountInWithFee = amountIn * (1000 - fee)
    numerator = amountInWithFee * reserveOut
    denominator = (reserveIn * 1000) + amountInWithFee
    amountOut = numerator / denominator
    return amountOut


amountIn = 5_000_000

amountOut = getAmountOut(amountIn,reserveA,reserveB)

print("amountOut " + str(amountOut))