// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";

contract MD2 {
    uint256 public constant OFFSET_LEFT = 16;
    uint256 public constant OFFSET_RIGHT = 208;
    uint256 public constant BUCKET_DURATION = uint256(7 days);
    uint256 public constant TOTAL_VESTING_PERIODS = OFFSET_RIGHT - OFFSET_LEFT;
    mapping(uint256 => mapping(address => WeeklyReward)) public rewards;
    uint256 public immutable GENESIS_TIMESTAMP;

    //TODO: make sure when we add a brand new grc,we need to
    // make sure that it doesent look backwards forever.
    mapping(address => BucketTracker) public bucketTracker;

    /**
     * @dev a helper to keep track of last updated bucket ids for buckets
     * @param lastUpdatedBucket - the last bucket + 16 that grc was deposited to this bucket
     * @param maxBucketId - the lastUpdatedBucket + 192
     */
    struct BucketTracker {
        uint128 lastUpdatedBucket;
        uint128 maxBucketId;
    }

    /**
     * @dev a helper function for {getBatchAddressesRewards}
     * @param token - the grcToken the user is querying for
     * @param reward - the weekly reward struct
     */
    struct TokenWithWeeklyReward {
        address token;
        WeeklyReward reward;
    }

    /**
     * @dev a struct to help track the amoutn in weekly rewards
     * @param inheritedFromLastWeek - a flag to see if the bucket has inherited
     *             -   it's vesting amount from past buckets using recursion
     * @param amountInBucket - the current amount in the bucket available as rewards
     * @param amountToDeduct - the amount to deduct from the {amountInBucket} when it initializes itself
     */
    struct WeeklyReward {
        bool inheritedFromLastWeek;
        uint256 amountInBucket;
        uint256 amountToDeduct;
    }

    constructor() {
        GENESIS_TIMESTAMP = block.timestamp;
    }

    function currentBucket() public view returns (uint256) {
        return (block.timestamp - GENESIS_TIMESTAMP) / BUCKET_DURATION;
    }

    function addToCurrentBucket(address grcToken, uint256 amount) public {
        uint256 currentBucketId = currentBucket();
        uint256 bucketToAddTo = currentBucketId + OFFSET_LEFT;
        uint256 bucketToDeductFrom = bucketToAddTo + TOTAL_VESTING_PERIODS;
        uint256 amountToAddOrSubtract = amount / TOTAL_VESTING_PERIODS;
        BucketTracker memory _bucketTracker = bucketTracker[grcToken];

        if (currentBucketId == 0) {
            rewards[bucketToAddTo][grcToken].amountInBucket += amountToAddOrSubtract;
            rewards[bucketToDeductFrom][grcToken].amountToDeduct += amountToAddOrSubtract;
            rewards[bucketToAddTo][grcToken].inheritedFromLastWeek = true;
            if (_bucketTracker.lastUpdatedBucket != bucketToAddTo) {
                bucketTracker[grcToken] =
                    BucketTracker(uint128(bucketToAddTo), uint128(bucketToAddTo + TOTAL_VESTING_PERIODS - 1));
            }
            return;
        }

        WeeklyReward memory currentBucket = rewards[bucketToAddTo][grcToken];
        if (currentBucket.inheritedFromLastWeek) {
            rewards[bucketToAddTo][grcToken].amountInBucket += amountToAddOrSubtract;
            rewards[bucketToDeductFrom][grcToken].amountToDeduct += amountToAddOrSubtract;
            return;
        }

        uint256 lastUpdatedBucket =
            _bucketTracker.lastUpdatedBucket == 0 ? bucketToAddTo : _bucketTracker.lastUpdatedBucket;
        WeeklyReward memory lastBucket = rewards[lastUpdatedBucket][grcToken];

        rewards[bucketToDeductFrom][grcToken].amountToDeduct += amountToAddOrSubtract;

        //This means that we don't need to look backwards
        //Since all the vested amount from that bucket would have been emptied by now if the bucket hadnt been refreshed in 192 weeks
        // If the lastUpdatedBucket is the current bucket, we also don't need to look backwards
        bool pastDataIrrelavant = bucketToAddTo > _bucketTracker.maxBucketId || lastUpdatedBucket == bucketToAddTo;
        uint256 totalToDeductFromBucket = pastDataIrrelavant ? 0 : currentBucket.amountToDeduct;

        if (!pastDataIrrelavant) {
            for (uint256 i = lastUpdatedBucket; i < bucketToAddTo; ++i) {
                totalToDeductFromBucket += rewards[i][grcToken].amountToDeduct;
            }
        }

        //If past data is irrelavant, then, lastBucket.amountInBucket should be 0,
        // and totalToDeduct
        rewards[bucketToAddTo][grcToken] =
            WeeklyReward(true, (lastBucket.amountInBucket + amountToAddOrSubtract) - totalToDeductFromBucket, 0);

        if (_bucketTracker.lastUpdatedBucket != bucketToAddTo) {
            bucketTracker[grcToken] =
                BucketTracker(uint128(bucketToAddTo), uint128(bucketToAddTo + TOTAL_VESTING_PERIODS - 1));
        }
    }

    function minBucket(uint256 forwardBucket) private view returns (uint256) {
        if (forwardBucket < TOTAL_VESTING_PERIODS) return OFFSET_LEFT;
        return forwardBucket - TOTAL_VESTING_PERIODS;
    }

    function getRewards(uint256 start, uint256 end, address grcToken) public view returns (WeeklyReward[] memory) {
        WeeklyReward[] memory _rewards = new WeeklyReward[](end - start);
        for (uint256 i = start; i < end; i++) {
            _rewards[i] = this.reward(grcToken, i);
        }
        return _rewards;
    }

    function getBatchAddressesRewards(uint256 start, uint256 end, address[] calldata tokens)
        external
        view
        returns (TokenWithWeeklyReward[] memory)
    {
        unchecked {
            uint256 totalRewards = tokens.length * (end - start);
            TokenWithWeeklyReward[] memory _rewards = new TokenWithWeeklyReward[](totalRewards);

            uint256 counter;
            for (uint256 i; i < tokens.length; ++i) {
                for (uint256 j = start; j < end; ++j) {
                    WeeklyReward memory wReward = this.reward(tokens[i], j);
                    _rewards[counter++] = TokenWithWeeklyReward(tokens[i], wReward);
                }
            }
            return _rewards;
        }
    }

    function reward(address grcToken, uint256 id) external view returns (WeeklyReward memory) {
        WeeklyReward memory bucket = rewards[id][grcToken];
        if (bucket.inheritedFromLastWeek || id < 16) {
            return bucket;
        }

        BucketTracker memory _bucketTracker = bucketTracker[grcToken];
        if (id > _bucketTracker.maxBucketId) {
            return bucket;
        }

        uint256 amountToSubtract = bucket.amountToDeduct;
        uint256 lastBucketId = id - 1;
        // uint timesTraversed;
        while (true) {
            WeeklyReward memory lastBucket = rewards[lastBucketId--][grcToken];
            amountToSubtract += lastBucket.amountToDeduct;
            if (lastBucket.inheritedFromLastWeek) {
                bucket.amountInBucket = lastBucket.amountInBucket - amountToSubtract;
                break;
            }

            // ++timesTraversed;
        }
        return bucket;
    }
}
