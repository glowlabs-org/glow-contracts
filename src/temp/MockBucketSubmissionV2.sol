// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "@/MinerPoolAndGCA/BucketSubmissionV2.sol";

contract MockBucketSubmissionV2 is BucketSubmissionV2 {
    function addToCurrentBucket(address token, uint256 amount) external {
        _addToCurrentBucket(token, amount);
    }

    function getAmountForTokenAndInitIfNot(address token, uint256 bucketId) public returns (uint256) {
        return _getAmountForTokenAndInitIfNot(token, bucketId);
    }

    function rawRewardInStorage(address token, uint256 bucketId) public view returns (bool, uint256, uint256) {
        BucketSubmissionV2.WeeklyReward memory reward = rewards[token][bucketId];
        return (reward.inheritedFromLastWeek, reward.amountInBucket, reward.amountToDeduct);
    }

    function setBucketTracker(address token, uint48 lastUpdatedBucket, uint48 maxBucketId, uint48 firstAddedBucketId)
        external
    {
        bucketTracker[token] = BucketTracker(lastUpdatedBucket, maxBucketId, firstAddedBucketId);
    }

    function genesisTimestampInternal() public view returns (uint256) {
        return _genesisTimestamp();
    }
}
