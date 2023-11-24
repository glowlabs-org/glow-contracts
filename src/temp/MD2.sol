// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "@/MinerPoolAndGCA/BucketSubmission.sol";

contract MD2 is BucketSubmission {
    function addToCurrentBucket(uint256 amount) external {
        _addToCurrentBucket(amount);
    }

    function getAmountForTokenAndInitIfNot(uint256 bucketId) public returns (uint256) {
        return _getAmountForTokenAndInitIfNot(bucketId);
    }

    function rawRewardInStorage(uint256 bucketId) public view returns (bool, uint256, uint256) {
        BucketSubmission.WeeklyReward memory reward = rewards[bucketId];
        return (reward.inheritedFromLastWeek, reward.amountInBucket, reward.amountToDeduct);
    }

    function genesisTimestampInternal() public view returns (uint256) {
        return _genesisTimestamp();
    }
}
