# Early Liquidity Testing Methodology


## Links
<a href="https://glow-docs.vercel.app/contracts#glow" target="_blank">
Glow Token Documentation
</a>


## Foundry-Tests

### Set-Up
The ```setUp``` function initializes all contract dependencies and
selects our fuzzing targets that will be called during fuzz and invariant runs.

The glow contrat tests use modifiers based off the branching tree technique in combination to more traditional syntax for test-writing.



### test_Mint
Starts a prank as SIMON, and mints tokens to SIMON from the faux Glow Contract.


### test_Stake
This tests uses the branching tree technique.
1. Mint 1e9 tokens to SIMON
2. Stake the entire balance of SIMON
3. Ensure simon is staking 1e9 tokens 
4. Ensure staking zero tokens should revert
5. Ensure that staking more than Simon's balance should revert
6. Mint 1e9 tokens to simon again
7. Stake the entire balance again
8. Make sure that simon now has 1e9 * 2 tokens


### test_stakeAndUnstake
1. Mint 1e9 tokens to SIMON
2. Stake 1 token
3. Ensure that only one token was staked
4. Unstaking more than than numStaked should fail
5. We try manually unstaking 1.1 tokens and making sure that reverts
6. We unstake 1 ether worth of tokens
7. We ensure that SIMON now has 0 tokens staked


### test_StakeAndUnstake_SinglePosition
This test is designed to test if unstaking correctly appends to a user's unstaked position
1. Mint 1e9 tokens to SIMON
2. Stake 1 token
3. Ensure 1 token is staked
4. Unstake 1 ether
5. Ensure that SIMON has 1 unstaked dposiiton
6a. Ensure the unstaked position's cooldown end is the unstake timestamp + 5 years
6b. Ensure the amount inside the unstaked position is 1 token



### test_StakeAndUnstake_SinglePosition_stakingShouldClaimGLOW
When users stake glow, they are allowed to pull from their unstaked positions. For example, if a user has 100 tokens in their unstaked positions, they can reuse those pending tokens to stake. This means that users do not need to put up fresh tokens every single time they stake. If users have tokens in their unstaked positions that are not yet claimed, the stake function handles the claim for the user. This means that if a user has 10 tokens that are ready to be claimed and wants to stake 1 token, the user will actually receive 9 tokens, (and also not have to send any tokens) when they go to stake that 1 token. This tests focusese on that logic.

1. Repeats all steps inside ```test_StakeAndUnstake_SinglePosition_stakingShouldClaimGLOW``` above.
2. Fast forwards to the cooldown end of the unstaked position
    -   This means that the 1 token inside the unstaked position is ready to be claimed
3. Perform some sanity checks
    -   a. Ensure the amount in the unstake position is still 1 token
    -   b. Ensure that we have zero tokens staked
4. Stake .5 tokens
5. Ensure that SIMON, RECEIVED, .5 tokens
    -   Since we are staking .5 tokens and have 1 token that is ready to be claimed
        The expected behavior is that SIMON receives .5 of that unstaked token and uses the rest to cover his new stake
6. Ensure that unstaked positons is correctly updated and that there are now no unstaked positions left.

### test_StakeAndUnstakeMultiplePositions_allExpired
This test is meant to be the same as the test above, except it tests claiming unstaked positions across multiple positions as opposed to just one. This ensures that looping is correctly happening and values are correctly being adjusted.

1. Create 10 unstaked positions each with a different expiration and amount for a total of 55 tokens
    - Check the ```stageStakeAndUnstakeMultiplePositions``` for more information
2. Fast forward to the final position's cooldown
3. Ensure that SIMON has 0 staked (sanity check)
4. Try staking 3 tokens
5. Make sure that we receive 52 tokens
    -   We had a total of 55 tokens across unstaked positions and now we want to stake 3 tokens. The contract should refund us 52 tokens and keep 3 tokens to stake with
6. Make sure all unstaked positions are cleared.
 

### test_StakeAndUnstakeMultiplePositions_noneExpired
This test checks to see the reaction of the Glow contract when none of the unstaked positions have expired. The expected behavior is that the glow contract should pull from unstaked positions when a user goes to stake.

1. Create 10 unstaked positions each with a different expiration and amount for a total of 55 tokens
    - Check the ```stageStakeAndUnstakeMultiplePositions``` for more information
2. Stake 2.5 tokens
3. Ensure that we have 2.5 tokens staked
4. Pull all unstaked posiitons
5. The first and second unstaked positions should have 1 token and 2 tokens respectively. By staking 2.5 tokens, we expect that the contract will use the full 1 token in the unstaked position and 1.5 of the tokens in the second unstaked position to fulfill this 2.5 token stake request. This means, we can expect the tail of the unstaked position to move up 1 (or the length of the unstaked positions to decrease by 1)
6. Ensure that new array length has decreased by 1.
7. Loop through the unstaked positions.
    -   If first position, ensure that the new amount inside that unstaked position is .5 tokens. This is because we needed to pull 1.5 tokens from the 2 tokens that existed in that unstaked position previously.
    - For the rest of the positions, ensure that the amounts stayed the same.


### test_StakeAndUnstakeMultiplePositions_oneExpiredStakeOne
This test checks to make sure that when a user has multiple unstaked positions, with the first that is ready to be claimed, that a stake correctly updates state. If a user has a position(s) that is ready to be claimed, the glow contract should look to pull from other unstaked positions first if it can. The idea here is that it takes a long time for a position to be able to be claimed, so, it's better to give users the benefit of the doubt by ensuring that the amount to stake if first pulled from their unstaked positions that have not yet expired, and if needed, also pull from those expirerd positions.

1. Create 10 unstaked positions each with a different expiration and amount for a total of 55 tokens
    - Check the ```stageStakeAndUnstakeMultiplePositions``` for more information
2. Fast forward to the end of the first unstaked position's expiration
3. Stake 1 token (the amount inside the first position)
4. Read unstaked positions
5. Ensure that the new user's unstaked positions doesent include the claimable unstaked position
6. Ensure that the unstaked position in the first index has been deducted by 1 token (since the function should pull from unstaked positions before pulling from claimable positions)
7. Ensure the user's balance of GLOW has increased by 1 token 
    -   This is because the stake function should claim tokens for the user if they are ready to be claimed



### test_StakeAndUnstakeMultiplePositions_useAllStakePositions
1. Create 10 unstaked positions each with a different expiration and amount for a total of 55 tokens
    - Check the ```stageStakeAndUnstakeMultiplePositions``` for more information
2. Sanity check to make sure the lenght of unstaked positions is 10
3. Stake 55 tokens (the total of tokens that we have previously unstaked in step 1)
4. Ensure that the user's balance hasn't changed after staking 55
    -   This is because the new stake of 55 tokens should be exactly fulfilled by the amount in our unstaked position
5. Ensure that all previous unstakked positions are deleted
6. Ensure that we have 55 tokens staked in the contracts
7. Mint some more faux glow tokens
8. Stake 1 token
9. Ensure that our balane has actually decreased by 1 token since we no longer have unstaked positions
9. Ensure that we have 56 tokens staked
10. Unstake .5 tokens
Ensure that we have 1 unstaked position with .5 tokens in it
11. Stake 1.5 tokens
12. Make sure that our token balance actually decreased by 1 token
    - This is because we unstaked .5 tokens and are now trying to stake 1.5 tokens
    - .5 tokens should be covered by our unstaked position
13. Make sure that we have a total of 57 tokens stasked
14. Ensure we no longer have any staked positions
    -   Should have been used up in our last stake


### test_UnstakeOver100ShouldForceCooldown
Once users have over 100 unstaked positions, we create a time-lock where they can only unstake every 24 hours until those positions have cleared. This is to prevent users from DoSing themselves or causing them to incur unexpectedly high gas fees when claiming tokens. This test is meant to check that logic.

1.  Warp forward to make sure we don't start at timestamp 0 (simulate more of a real world environemnt -- we could also create a fork but we choose not to)
2. Mint 1e9 tokens to simon
3. Stake 1e9 tokens
4. Create 100 unstaked positions
5. We expect the next unstaked position to revert since it will be our 101'st position
6. We fast forward by the ```EMERGENCY_COOLDOWN_PERIOD``` and test staking to make sure it works.
7. We repeat 1-6 again to ensure the functionality works as expected throughout iterations


### test_ClaimZeroTokensShouldFail
We test that claiming 0 tokens should revert

### test_ClaimTokens
1. Mint and stake tokens
2. Unstake tokens
3. Fast forward 5 minutes
4. Try claiming those tokens
    -   This should revert since it's not been 5 years since we unstaked
5. Fast forward 5 years
6. Claim all of those tokens
6. Ensure that we correctly claimed all of those tokens and that the unstaked position is deleted


### test_ClaimTokens_ClaimableTotalGT_Amount_NoNewTail
The same as above except that we claim tokens less than the amount that we've unstaked. In this test we check to ensure that 
1. Our unstaked positions was not deleted, but rather updated to reflect the new amount that should be inside the unstaked position
2. The amount inside the unstaked position is properly updated.


### test_ClaimTokens_ClaimableTotalGT_Amount_NewTail
This test is an extension of the test above. We create two unstaked positions, one with .01 tokens and one with .99 tokens.  This test ensures that balanaces are being correctly updated when a claim has to traverse multiple unstaked balanaces.
We then claim .1 tokens. We ensure that:
1. We actually received .1 tokens
2. The first unstaked position (.01 tokens) is deleted
3. The last unstaked position (.99 tokens) is correctly decremented by (.1-.01) tokens


## Inflation Tests
The inflation tests are rather straightforward and aim to ensure that only the approved entities can claim their designated GLOW tokens, and that the contract should be correctly only able to set the GCA,Veto Council, and Grants Treasury contracts on time.


## Unstaked Positions (view) function tests
TODO: Start from here

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