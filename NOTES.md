Maybe?
--Make claimFromInflation a different function for miner pool and gcas even though they're in the same contract.

-----AUCTION----
1. Add refunds

----- GCC -----
1. Remove (to) in docs on retire functions 
2. Remove public domain seperator into private and make it public in test files.
3. decide if 712 signatures for retiring allowance should also work on transfer amounts....
4. get rid of increase and decrease and just have a standard set?

---GCA---
1. Finish pending payout
2. add max gcas
3. include freeze when proposal hashes isnt up to date
4. Finish implementing global state!

---- GOVERNANCE AND HALF LIFE ------
Thought about two ways we could handle the math.
1. We require retiring of credits in .1 increments so that we can demagnify in the Nominations struct.
    -  Should be virtually impossible to exhaust that number especially since a max of 5 trillion gcc is minted per week 
    - Pros:
        1. More Simple
        2. Less Gas
    - Cons:
        1. Establishes a modular rule that users need to follow when retiring.
    
2. We could split up the large amounts into smaller amounts and run individual half-life functions on the smaller parts.
    - Pros:
        1. Flexible and doesen't require mod based amounts (increments) to be retired
    - Cons:
        1. More complex
        2. more gas


---- EARLY LIQUIDITY --------
1. Add calculus integration to early liquidity section
2. Figure out with david if we need fulfill partial order
3. Finish Interface

---- VETO COUNCIL ----
1. Finish payout algo
2. Make sure there's a check to reestablish the total shares after add or remove event where newLength != oldLength

Extra:
According to some tests I ran, cost about 15K gas for a half life calculation

---NOTES:
1. list max and min gas prices for each major function
2. min increment for anything smaller than 1 ether fails, so we can't decrease the min increment