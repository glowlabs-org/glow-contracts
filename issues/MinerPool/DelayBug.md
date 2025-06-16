# Delay Bug

## Description Of Bug
If a GCA is slashed and the slash nonce is incremented, the WCEIL of the report
is based on the `proposalCreationTimestamp` which could be way in the past.
This can cause a bucket that is finalized to become unfinalized, and could also make it so that delayed buckets can never be resubmitted.

Here is a code example
```solidity
function test_submitReportAsGCA() public {
        vm.startPrank(gca);

        vm.warp(block.timestamp + 3 weeks);
        uint256 currentBucket = minerPoolAndGCA.currentBucket();
        //Issue a report
        minerPoolAndGCA.submitWeeklyReport(currentBucket, 1, 1, 1, bytes32(uint256(0x2)));

        vm.warp(block.timestamp + 1 weeks);
        currentBucket = minerPoolAndGCA.currentBucket();
        //Issue a report
        minerPoolAndGCA.submitWeeklyReport(currentBucket, 1, 1, 1, bytes32(uint256(0x2)));

        vm.warp(block.timestamp + 1 weeks);
        currentBucket = minerPoolAndGCA.currentBucket();

        //Before syncing, let's check if current bucket -2 has finalized
        console.log("Is bucket - 2 finalized = ", minerPoolAndGCA.isBucketFinalized(currentBucket - 2));

        gov.syncProposals();

        //Log bucket -2 after the sync
        console.log("Is bucket - 2 finalized = ", minerPoolAndGCA.isBucketFinalized(currentBucket - 2));
        address[] memory gcasToSlash = new address[](1);
        /**
         * agentsToSlash	address[]	0xB2d687b199ee40e6113CD490455cC81eC325C496
         * 1	newGCAs	address[]	0x63a74612274FbC6ca3f7096586aF01Fd986d69cE
         * 0xda025d5FE4485e191245FAad55a3a6e674979391
         */
        gcasToSlash[0] = 0xB2d687b199ee40e6113CD490455cC81eC325C496;
        address[] memory newGCAs = new address[](2);
        newGCAs[0] = 0x63a74612274FbC6ca3f7096586aF01Fd986d69cE;
        newGCAs[1] = 0xda025d5FE4485e191245FAad55a3a6e674979391;
        uint256 proposalCreationTimestamp = 1728763019;

        //Log the slash nonce
        console.log("Slash nonce = ", minerPoolAndGCA.slashNonce());

        minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);

        // Can we issue the report?
        vm.expectRevert();
        minerPoolAndGCA.submitWeeklyReport(40, 1, 1, 1, bytes32(uint256(0x2)));

        vm.stopPrank();
    }
```

## The Fix
The fix is achieved by making sure that the `slashNonceToSlashTimestamp` is set to `block.timestamp` when the `slashNonce` is incremented

### Code Before:
GCA.pushHash(): function

The hash is incremented here
```solidity
     if (incrementSlashNonce) {
            ++slashNonce;
        }
```
and then `slashNonceToSlashTimestamp[slashNonce]` is set to the proposal creation timestamp.

GCA.executeAgainstHash(): function

```solidity
        if (gcasToSlash.length > 0) {
            slashNonceToSlashTimestamp[slashNonce - 1] = proposalCreationTimestamp;
        }
```

### Code After:
GCA.pushHash(): function
```solidity
      if (incrementSlashNonce) {
            slashNonceToSlashTimestamp[slashNonce++] = block.timestamp;
        }
```

The code from `GCA.executeAgainstHash()` is removed as it is no longer needed.


### Why The Fix Works


### Tests Added

* MinerPoolAndGCAV2.t.sol::test_v2_increment_slashNonce_shouldAllowForResubmissions_if_bucketDelayed
