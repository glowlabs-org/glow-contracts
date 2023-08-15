Maybe?
--Make claimFromInflation a different function for miner pool and gcas even though they're in the same contract.


----- GCC -----
1. Remove (to) in docs on retire functions 
2. Remove public domain seperator into private and make it public in test files.
3. decide if 712 signatures for retiring allowance should also work on transfer amounts....


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
According to some tests I ran, cost about 15K gas for a half life calculation