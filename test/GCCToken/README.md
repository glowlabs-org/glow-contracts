# Early Liquidity Testing Methodology


## Links
<a href="https://glow-docs.vercel.app/contracts#gcc" target="_blank">
GCC Token Documentation
</a>


## Foundry-Tests

### Set-Up
The ```setUp``` function initializes all contract dependencies and
selects our fuzzing targets that will be called during fuzz and invariant runs.

### invariant_setBucketMintedBitmapLogic
We make sure that the bucketMintedBitmap is set correctly by creating
 a stateful fuzz that tracks all used bucketIds


### test_sendToCarbonCreditAuction
This test ensures that the GCC contract is correctly minting to the carbon credit auction contract.

### test_sendToCarbonCreditAuction_callerNotGCA_shouldRevert
This test ensures that only the GCA and Miner Pool contract can use the ```mintToCarbonCredit``` function.

### test_sendToCarbonCreditAuctionSameBucketShouldRevert
This test ensures that we can only mint from a bucket once

### test_retireGCC
In this test we mint some faux GCC to simon which he retires.
We check that his balance after retiring all of those minted tokens should be zero and that his total carbon neutrality should be equal to the amount of credits he retired.
Nominations need to be tested in the Governance test suite to ensure Governance properly handles the acceptance and depreciation of nominations.

### test_retireGCC_GiveRewardsToOthers
This is the same as the test above, except that SIMON designates a wallet called "other" in which to send the neutrality. This test ensures that the "other" wallet correctly receives that neutrality.


### test_retireGCC_ApprovalShouldRevert
This test pranks as an "other" address and tries to retireGCCFor SIMON.
It expects a revert since the other account does not have permission to transfer any ERC20 tokens on behalf of the user.


### test_setRetiringAllowance_single
This test ensures that the contract is correctly increasing and decreasing retiring allowances. Retiring allowances are similar to ERC20 allowances. Users can allow other entities to retire on their behalf.

### test_setRetiringAllowances_overflowShouldRevert
This test ensures that increasing approvals reverts on overflow.


### test_setRetiringAllowances_underflowShouldRevert
This test ensures that decreasing approvals should revert on underflow.

### test_setRetiringAllowance_Double
This function tests the functionality of ```increaseAllowances``` and ```decreaseAllowances```. This function is a helper that allows an address to simultaneously increase or decrease both the ERC20 allowances as well as the retiring allowances for a specified spender in one transaction.


### test_retireGCC_onlyRetiringApproval_shouldRevert
This function ensures that retiring on behalf of another user should fail it you don't have enough ERC20 allowance but you do have enough retiring allowance.

### test_retireGCC_ApprovalShouldWork
This function checks that when you do have proper allowances, that you should be able to retire on somebody else's behalf.


### test_retireGCC_Signature
We check that users can grant an address retiring allowance using a signature similar to Permit in ERC20. If users don't have enough approval allowance, the ```retireForGCCAuthorized``` function bumps up the retiring allowance to allow only those tokens requested to be retired.

### test_retireGCC_Signature_badSignature_shouldFail
This test checks to make sure that retiring with signatures should revert if the deadline on the signature has already passsed.

### test_retireGCC_Signature_badSignature_shouldFail
This function tests that incoherent signatures don't pass signature validation.


### test_retireGCC_badSigner_shouldFail
This test checks that only the EoA account that wants to approve an external entity can provide a signature to increase the allowance of that spender. All other signers should fail.





## Testing Checklist
    -   enumerate all arrays to look for infinite length bugs
        -   This contract does not contain any loops
    -   enumerate all additions to look for overflows
        - a1) overflow could happen in the retiring allowances, but built in safemath prevents reverts
    -   enumerate all multiplications to look for overflows
            -  There is no multiplication occuring
            - However, there is bit shifting happening for tracking bucket statuses. Those are safe since MAX_SHIFT is 255
    -   enumerate all subtractions to look for underflows
            -   same as a1
    -   enumerate all divisions to look for divide by zero
        -   There is only one division occuring and it is by a hard-coded value of MAX_SHIFT(255)
    -   enumerate all divisions to look for precision issues
        -   no precision issues
    -   reentrancy attacks
        -   There are no cross-contract calls being made to unauthorized actors
    -   frontrun attacks
        -   Signature based Approvals can be front-run by integrators. However, this is not an issue since integrators should be properly aware of how to integrate signature based approvals. It's the same concept as ERC20 permit and there is a lot of great information out there already.
    -   censorship attacks
        -   N/A
    -   DoS with block gas limit
        -   n/a
    -   checks and effects pattern
        - All storage writes happen after reads.
    -   logic bugs
        -   TBD
    -   cross-contract bugs
        -   only cross contract calls to known actors