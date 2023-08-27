# Early Liquidity Testing Methodology


## Links
<a href="https://glow-docs.vercel.app/contracts#earlyliquidity" target="_blank">
Early Liquidity Documentation
</a>


## Foundry-Tests

### Set-Up
The ```setUp``` function initializes all contract dependencies and
selects our fuzzing targets that will be called during fuzz and invariant runs.


### invariant_earlyLiquidityShouldNeverHaveMoreThan12Mil
This invariant simply checks that the balance of earlyLiquidity
should always be less than or equal to 12 Million (its initial starting balance).

### invariant_priceShouldNeverBeGreaterThanMaxPrice
This invariant checks that the current price of the token
is never greater than the max price. It also checks to make sure
the price for x tokens is never greater than the max price of tokens * x.
The purpose of this invariant is to have a sanity check that will detect if 
our floating point math has any major bugs.


### test_setGlowAndMint
Tests that setting the Glow token functions as intended

### test_Buy
Tests that reading from the ```getPrice``` function and then executing a 
```buy```  results in a succesful transaction that sends Glow to the buyer,
and transfers USDC from the user. It also checks that once Glow has been sold, the next ```getPrice``` function with the same ```amount``` returns a higher price. This is necessary since the price of tokens increase along a bonding curve.


### test_Buy_checkUSDCGoesToMinerPool
This test is a continuation of the above test, except thata it also ensures that USDC was correctly transferred to the ```minerPool``` contract.
The ```minerPool``` used in this environment is a mock miner pool contract. This is not an integration test between the two final contracts, but just a helper to ensure that USDC is being sent correctly.

### test_Buy_checkUSDCGoesToMinerPool_taxToken
This test is a continuation of the above test, but ensures that the ```EarlyLiquidity``` contract peroprly handles sending the correct values in the case that USDC decides to add a tax on transfers.


### test_Buy_priceTooHigh_shouldFail
This function ensures that if the price for the tokens is higher than the user's max price, the buy function should fail.

### test_Buy_modNotZeroShouldFail
Due to the nature of floating point math restrictions in the ```ABDKMath64x64 Library```, the smallest token increment to buy is 1e18 tokens. That means, users cannot buy 1 ether + 1 tokens for example. They can only buy in increment of 1 ether. This test ensures that amounts being passed in to the buy function are abiding by this rule.

### test_setGlowTokenTwice_shouldFail
Tests to make sure that once Glow is set, it cannot be set again.

### test_getCurrentPrice
Tests that the price for the first token should fall within 1 wei (to adjust for potential rounding errors) within our expected price of .6 USDC.



## Hardhat Tests
The pricing for our tokens follows an exponential curve where the price of a token x is equal to ```f(x) = .6 * 2^((total tokens sold + x)/1_000_000)```
This ensures that the price doubles every 1 million tokens sold. In order to calculate the price in Solidity, we use a geometric series to sum up the price of all the tokens. Due to the floating point nature of Solidity (rounding errors, etc), we use Hardhat to run a custom fuzzing test where we compare the Solidity output of the price to the actual expected output over multiple buy operations. This ```actual expected output``` is found by looping over each individual token that is being sold in the buy function. We then ensure that the outputs from Solidity don't diverge further than .01% from the expected output. If that passes, the test will pass. For sanity checks, we also write the data to CSV's found in the data folder to manually verify that the test is working as expected. This can me modified in your ```.env``` file.




## Testing Checklist
    -   enumerate all arrays to look for infinite length bugs
        -   This contract does not contain any loops
    -   enumerate all additions to look for overflows
        -   potential overflows and why they aren't possible are explained:
            -  ```_getFirstTimeInSeries```
            -   ```_getPrice```
    -   enumerate all multiplications to look for overflows
            -  ```_getFirstTimeInSeries```
            -   ```_getPrice```
    -   enumerate all subtractions to look for underflows
            -  ```_getFirstTimeInSeries```
            -   ```_getPrice```
    -   enumerate all divisions to look for divide by zero
        -   Divison by zero is not possible since any values we divide by are hard-coded
    -   enumerate all divisions to look for precision issues
        -   Handled in the hardhat test
    -   reentrancy attacks
        -   Cross contract calls are only being made to USDC and to the Miner Pool Contract. None of which are attackers. Furthermore, the contract falls the checks and effects pattern.
    -   frontrun attacks
        -   Technically it is possible to frontrun a person's buy transaction in order to cause them to revert, but keeping up this sort of attack over an extended period of time would require a large amount of funds
        to purchase tokens (USDC) as well as to pay the gas (ETH).
    -   censorship attacks
    -   DoS with block gas limit
        -   There are no such data structures in which users could DoS themselves or DoS others
    -   proper access control
        -   Setting the Glow contract could be front-run, but this is highly unlikely since the Glow team will be deploying contracts from an anonymous wallet.
    -   checks and effects pattern
        - All storage writes happen after reads.
    -   logic bugs
        -   TBD
    -   cross-contract bugs
        -   Cross-contract calls are explicitly checked in the ```test_Buy_checkUSDCGoesToMinerPool``` function