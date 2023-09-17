// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";

contract BucketSubmission {
    /**
     * @notice the start offset to the current bucket for the grc deposit
     * @dev when depositing grc, the grc is evenly distributed across 192 weeks
     *         -   The first bucket to receive grc is the current bucket + 16
     *         -   The last bucket to receive grc is the current bucket + 208
     */
    uint256 public constant OFFSET_LEFT = 16;

    /**
     * @notice the end offset to the current bucket for the grc deposit
     * @dev the amount to offset b(x) by to get the final bucket number where the grc will have finished vesting
     *         - where b(x) is the current bucket
     */
    uint256 public constant OFFSET_RIGHT = 208;

    /// @dev each bucket is 1 week long
    uint256 public constant BUCKET_DURATION = uint256(7 days);

    /// @notice a constant holding the total vesting periods for a grc donation (192)
    uint256 public constant TOTAL_VESTING_PERIODS = OFFSET_RIGHT - OFFSET_LEFT;

    /// @notice mappings bucketId -> grcToken -> WeeklyReward
    mapping(uint256 => mapping(address => WeeklyReward)) public rewards;

    /// @notice grcToken -> bucketTracker
    mapping(address => BucketTracker) public bucketTracker;

    /**
     * @dev a helper to keep track of last updated bucket ids for buckets
     * @param lastUpdatedBucket - the last bucket + 16 that grc was deposited to this bucket
     * @param maxBucketId - the lastUpdatedBucket + 192
     */
    struct BucketTracker {
        uint48 lastUpdatedBucket;
        uint48 maxBucketId;
        uint48 firstAddedBucketId;
        bool isGRC;
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

    //************************************************************* */
    //*****************  EXTERNAL STATE CHANGING FUNCS  ************** */
    //************************************************************* */

    function _addToCurrentBucket(address grcToken, uint256 amount) internal {
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
                //TODO: Could also swtich to true for the last param since we check in the external func
                bucketTracker[grcToken] = BucketTracker(
                    uint48(bucketToAddTo),
                    uint48(bucketToAddTo + TOTAL_VESTING_PERIODS - 1),
                    _bucketTracker.firstAddedBucketId,
                    _bucketTracker.isGRC
                );
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
            bucketTracker[grcToken] = BucketTracker(
                uint48(bucketToAddTo),
                uint48(bucketToAddTo + TOTAL_VESTING_PERIODS - 1),
                _bucketTracker.firstAddedBucketId,
                _bucketTracker.isGRC
            );
        }
    }

    //************************************************************* */
    //***************  EXTERNAL/PUBLIC VIEW FUNCTIONS  ************ */
    //************************************************************* */

    function currentBucket() public view returns (uint256) {
        return (block.timestamp - _genesisTimestamp()) / BUCKET_DURATION;
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
        (WeeklyReward memory bucket,) = _rewardWithNeedsInitializing(grcToken, id);
        return bucket;
    }

    //TODO: Check if this returns correctly on unitialized buckets.
    //TODO: When the bucket is being withdrawn from, if it's not yet init,
    //          -   make sure that it gets init so we dont need to spend time looking backwards
    /**
     * @notice returns the weekly reward for a given bucket
     * @dev if the bucket has not yet been initialized,
     *             - the function will look backwards to calculate the correct amount
     *             - if the bucket has been initialized, it will return the bucket
     * @param grcToken - the address of the grcToken
     * @param id - the bucketId to query for
     * @return bucket - the  weekly reward struct for the bucket
     * @return needsInitializing -- flag to see if the bucket needs to be initialized
     * @dev `needsInitializing` should be used in the withdraw reward function to see if the bucket needs to be initialized
     */
    function _rewardWithNeedsInitializing(address grcToken, uint256 id)
        internal
        view
        returns (WeeklyReward memory, bool)
    {
        WeeklyReward memory bucket = rewards[id][grcToken];
        // If the bucket has already been initialized
        // Then we can just return the bucket.
        if (bucket.inheritedFromLastWeek || id < 16) {
            return (bucket, false);
        }

        // If the index to search for is greater than the maxBucketId
        // than that means all the tokens would have vested,
        // So we return the empty bucket
        BucketTracker memory _bucketTracker = bucketTracker[grcToken];
        if (id > _bucketTracker.maxBucketId) {
            return (bucket, false);
        }

        uint256 amountToSubtract = bucket.amountToDeduct;
        uint256 lastBucketId = id - 1;

        uint256 firstUpdatedBucket = _bucketTracker.firstAddedBucketId;
        // ....check with david if i can leave while loop in here.
        while (true) {
            if (firstUpdatedBucket > lastBucketId) {
                break;
            }
            WeeklyReward memory lastBucket = rewards[lastBucketId--][grcToken];

            amountToSubtract += lastBucket.amountToDeduct;

            if (lastBucket.inheritedFromLastWeek) {
                bucket.amountInBucket = lastBucket.amountInBucket - amountToSubtract;
                break;
            }
        }
        return (bucket, true);
    }

    function getAmountForTokenAndInitIfNot(address grcToken, uint256 id) public returns (uint256) {
        (WeeklyReward memory reward, bool needsInitializing) = _rewardWithNeedsInitializing(grcToken, id);
        if (needsInitializing) {
            reward.inheritedFromLastWeek = true;
            rewards[id][grcToken] = reward;
        }
        return reward.amountInBucket;
    }

    //************************************************************* */
    //**************  INTERNAL/PRIVATE STATE CHANGING  ************ */
    //************************************************************* */

    /**
     * @notice sets the grc tracker for a token
     * @dev the external implementation should only be allowed to be called by governance
     * @param grcToken - the address of the token
     * @param adding - if true, this adds the token to the allowed grcTokens
     *                     - else it removes it
     */
    function _setGRCToken(address grcToken, bool adding, uint256 currentBucket) internal {
        BucketTracker storage _bucketTracker = bucketTracker[grcToken];
        if (adding) {
            // If this is the first time making the token a GRC
            // the firstAddedBucketId will be zero, so we need to set it.
            // If the currentBucket > maxBucketId -- that means that the bucket has zero vesting remaining so we can reset
            // the firstAddedBucketId to the current bucket. This makes lookups inside {reward} more efficient.
            if (_bucketTracker.firstAddedBucketId == 0 || currentBucket > _bucketTracker.maxBucketId) {
                _bucketTracker.firstAddedBucketId = uint48(currentBucket + OFFSET_LEFT);
            }
            if (!_bucketTracker.isGRC) {
                _bucketTracker.isGRC = true;
            }
        } else {
            _bucketTracker.isGRC = false;
        }
    }

    //************************************************************* */
    //**************  INTERNAL/PRIVATE VIEW  ************ */
    //************************************************************* */

    /// @dev this must be overriden inside the parent contract.
    function _genesisTimestamp() internal view virtual returns (uint256) {
        return 0;
    }
}
