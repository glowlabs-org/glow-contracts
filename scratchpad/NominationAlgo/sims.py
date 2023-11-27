
import math

gcc_decimals = 18
usdc_decimals = 6
nomination_decimals = 12 #  sqrt(1e24) = 1e12


amountGCCInLp = 500 * (10 ** gcc_decimals)
amountUSDCInLp = 100000000 * (10 ** usdc_decimals)
gccCommittment = 100 * (10 ** gcc_decimals)


class UniswapPair:
    def __init__(self, x, y, fee=0.003):
        """
        Initialize a Uniswap pair with reserves x and y and an optional fee.
        
        :param x: Reserve for asset x
        :param y: Reserve for asset y
        :param fee: Transaction fee (default is 0.3%)
        """
        self.x = x
        self.y = y
        self.k = x * y  # Constant product
        self.fee = fee

    def _update_reserves(self, x, y):
        """
        Update the reserves after a swap and ensure the invariant k is maintained.
        
        :param x: New reserve for asset x
        :param y: New reserve for asset y
        """
        self.x = x
        self.y = y
        self.k = self.x * self.y  # Recalculate the constant product

    def get_price(self, asset='x'):
        """
        Calculate the price of one asset in terms of the other.
        
        :param asset: The asset for which to calculate the price ('x' or 'y')
        :return: The price of the asset
        """
        if asset == 'x':
            return self.y / self.x
        elif asset == 'y':
            return self.x / self.y
        else:
            raise ValueError("Invalid asset type. Choose 'x' or 'y'.")
        
    def get_usdc_received_from_swap(self, amount_in, asset_out='x'):
        """
        Calculate the amount of one asset that will be received for the given amount of the other asset.
        
        :param amount_in: The amount of the input asset
        :param asset: The asset to be received ('x' or 'y')
        :return: The amount of the output asset
        
        uint256 amountInWithFee = amountIn * (997);
        uint256 numerator = amountInWithFee * (reserveOut);
        uint256 denominator = reserveIn * (1000) + (amountInWithFee);
        amountOut = numerator / denominator;
        """
        if asset_out == 'x':
            amountInWithFee = amount_in * (997)
            numerator = amountInWithFee * self.y
            denominator = self.x * (1000) + amountInWithFee 
            return numerator / denominator
        elif asset_out == 'y':
            amountInWithFee = amount_in * (997)
            numerator = amountInWithFee * self.x
            denominator = self.y * (1000) + amountInWithFee 
            return numerator / denominator
        else:
            raise ValueError("Invalid asset type. Choose 'x' or 'y'.")
    def swap_x_for_y(self, x_amount):
        """
        Swap x for y, considering the fee.

        :param x_amount: Amount of x to swap
        :return: Amount of y received
        """
        x_amount_with_fee = x_amount * (1 - self.fee)
        y_amount = self.y - (self.k / (self.x + x_amount_with_fee))
        self._update_reserves(self.x + x_amount_with_fee, self.y - y_amount)
        return y_amount

    def swap_y_for_x(self, y_amount):
        """
        Swap y for x, considering the fee.

        :param y_amount: Amount of y to swap
        :return: Amount of x received
        """
        y_amount_with_fee = y_amount * (1 - self.fee)
        x_amount = self.x - (self.k / (self.y + y_amount_with_fee))
        self._update_reserves(self.x - x_amount, self.y + y_amount_with_fee)
        return x_amount



def find_optimalAmount_to_commit(amountToCommit,reservesOfToken):
        a = math.sqrt(reservesOfToken) + 1
        b = math.sqrt(3988000 * amountToCommit + 3988009 * reservesOfToken)
        c = 1997 * reservesOfToken
        d = 1994
        res = ((a*b)-c)/d
        return res

import random 

def get_random(min:int,max:int):
    return random.randint(min,max)

pair = UniswapPair(amountGCCInLp, amountUSDCInLp)
print("amount to commit = ", gccCommittment)
print("total  reserves of token = ", amountGCCInLp)

#  amount to commit: 100000000000000000000000000000000000000
#   total reserves of token: 500000000000000000000000000000000000000
#   optimal amount to swap = 47794253577372892495
# amount out = 8700957737104.0
amount_gcc_using_in_swap = find_optimalAmount_to_commit(gccCommittment, amountGCCInLp)
usdc_received_from_swap = pair.get_usdc_received_from_swap(amount_gcc_using_in_swap)


def run_sim_impl(reserveGCC,reserveUSDC,amountGCCToCommit):
    pair = UniswapPair(reserveGCC, reserveUSDC)
    amount_gcc_using_in_swap = find_optimalAmount_to_commit(amountGCCToCommit, reserveGCC)
    usdc_received_from_swap = pair.get_usdc_received_from_swap(amount_gcc_using_in_swap)
    amount_gcc_using_in_liquidity = amountGCCToCommit - amount_gcc_using_in_swap
    amount_usdc_in_liquidity = usdc_received_from_swap
    nominations_earned = math.sqrt(amount_gcc_using_in_liquidity * amount_usdc_in_liquidity)
    return (
        reserveGCC / (10 ** gcc_decimals),
        reserveUSDC / (10 ** usdc_decimals),
        amountGCCToCommit / (10 ** gcc_decimals),
        amount_gcc_using_in_swap / (10 ** gcc_decimals),
        usdc_received_from_swap / (10 ** usdc_decimals),
        amount_gcc_using_in_liquidity / (10 ** gcc_decimals),
        amount_usdc_in_liquidity / (10 ** usdc_decimals),
        nominations_earned / (10 ** nomination_decimals)
    )

min = 10
max = 1000000000
def run_sim():
    reserveGCC = get_random(min,max) * (10 ** gcc_decimals)
    reserveUSDC = get_random(min,max) * (10 ** usdc_decimals)
    amountGCCToCommit = get_random(min,max) * (10 ** gcc_decimals)
    return run_sim_impl(reserveGCC,reserveUSDC,amountGCCToCommit)

def run_base_case():
    return run_sim_impl(amountGCCInLp,amountUSDCInLp,gccCommittment)
import csv

def run_sims(times_to_run:int):
    sims = []
    sims.append(run_base_case())
    for i in range(times_to_run):
        sims.append(run_sim())
    #make a csv
    with open('simulations.csv', 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["reserveGCC","reserveUSDC","amountGCCToCommit","amount_gcc_using_in_swap","usdc_received_from_swap","amount_gcc_using_in_liquidity","amount_usdc_in_liquidity","nominations_earned"])
        for i in sims:
            writer.writerow(i)
    print("done")

run_sims(100)

#21312906729426814
#21312.906729426817