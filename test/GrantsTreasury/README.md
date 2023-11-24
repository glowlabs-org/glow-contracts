# Early Liquidity Testing Methodology


## Links
<a href="https://glow-docs.vercel.app/contracts#grants-treasury" target="_blank">
Grants Treasury Documentation
</a>


## Foundry-Tests

### Set-Up
The ```setUp``` function initializes all contract dependencies and
selects our fuzzing targets that will be called during fuzz and invariant runs.

The glow contrat tests use modifiers based off the branching tree technique in combination to more traditional syntax for test-writing.


### test_AllocatingFromNotGovernanceShouldRevert
This test ensures that any non governance contracts cannot allocate grant funds.

### test_AllocationFromGovernanceShouldWork
This test ensures that the governance contract can allocate grant funds.

### test_AllocationShouldReturnFalse
This test ensures that if the grants treasury does not have enough to fulfill the amount that has been requested for allocation (from governance) it returns false.

### test_AllocationShouldReturnTrue
This test ensures that if the grantsTreasury does have enough to payout, it allocates grant funds.

### test_AllocationShouldReturnTrueAndRecipientShouldClaim
This function does the same as the above, but we claim as the recipient. The test then ensures that the transfer was succesful and that state variables were properly updated.

### test_actualBalanceTooLow
We allocate the entirety of the grants treasury balance to a recipient and do not claim from that recipient. We then test to ensure that any further allocation results in ```false``` meaning that allocation cannot be granted. We then claim from the user. This ensures that the grants treasury cannot allocate grant funds even if its ERC20 balance is high enough. The grants treasury must always check its ACTUAL balance which is equal to its balance - everything that it owes.

### test_ClaimZeroShouldRevert
This test claiming zero tokens reverts.


### test_SyncShouldPullFromInflation
This test ensures that sync() is properly working to pull glow tokens in accordance with the inflation schedule.


## Testing Checklist
    -   enumerate all arrays to look for infinite length bugs
        -   This contract does not contain any loops
    -   enumerate all additions to look for overflows
        - there are no worrying concerns for overflow.
    -   enumerate all multiplications to look for overflows
            -   multiplication is most apparent in the inflation claim functions..
            - those functions have been tested in this suite and appear to be free from overflow and significant rounding errors
    -   enumerate all subtractions to look for underflows
            -   underflow prevention is explained in the respective functions
                -   ```stake```
                -   ```claimUnstakedTokens```
                -   ```unstakedPositionsOf```
    -   enumerate all divisions to look for divide by zero
        -   There is no division occuring in this contract
    -   enumerate all divisions to look for precision issues
        -   handled in the test suite
    -   reentrancy attacks
        -   There are no cross-contract calls being made
    -   frontrun attacks
        -   There are no functions in this contract where front-running could be an issue.
    -   censorship attacks
        -   N/A
    -   DoS with block gas limit
        -   There are no such data structures in which users could DoS themselves or DoS others, specifically in the unstaking logic. The contract implements a restriction on users that have over 100 unstaked positions. This should prevent users from preventing unwanted harm to themsleves.
    -   proper access control
        -   Setting the contracts could be front-run, but this is highly unlikely since the Glow team will be deploying contracts from an anonymous wallet.
    -   checks and effects pattern
        - All storage writes happen after reads.
    -   logic bugs
        -   TBD
    -   cross-contract bugs
        -   No cross contract calls