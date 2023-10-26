// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";
import "@/MinerPoolAndGCA/BucketSubmission.sol";

contract MD2 is BucketSubmission {
    function addToCurrentBucket(address grcToken, uint256 amount) external {
        _addToCurrentBucket(grcToken, amount);
    }

    function addGRCToken(address grcToken) external {
        (bool res, BucketSubmission.BucketTracker memory tracker) = _setGRCTokenCheck(grcToken, true, currentBucket());
        _setGRCToken(grcToken, tracker);
    }

    function getAmountForTokenAndInitIfNot(address grcToken, uint256 bucketId) public returns (uint256) {
        return _getAmountForTokenAndInitIfNot(grcToken, bucketId);
    }

    function rawRewardInStorage(address grcToken, uint256 bucketId) public view returns (bool, uint256, uint256) {
        BucketSubmission.WeeklyReward memory reward = rewards[bucketId][grcToken];
        return (reward.inheritedFromLastWeek, reward.amountInBucket, reward.amountToDeduct);
    }

    function genesisTimestampInternal() public view returns (uint256) {
        return _genesisTimestamp();
    }
}
