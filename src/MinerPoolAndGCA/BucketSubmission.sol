// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract BucketSubmission {
    /**
     * @notice the start offset to the current bucket for the grc deposit
     * @dev when depositing grc, the grc is evenly distributed across 192 weeks
     *         -   The first bucket to receive grc is the current bucket + 16 weeks
     *         -   The last bucket to receive grc is the current bucket + 208 weeks
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

    /// @notice mappings bucketId -> WeeklyReward
    mapping(uint256 => WeeklyReward) internal rewards;

    /**
     * @dev a helper to cache the last updated bucket
     *         -   and the first bucket that USDC was deposited to
     *         -   and the last bucket that USDC was deposited to
     */
    BucketTracker internal bucketTracker;

    /**
     * @dev a helper to keep track of last updated bucket ids for buckets
     * @param lastUpdatedBucket - the last bucket + 16 that grc was deposited to this bucket
     * @param maxBucketId - the lastUpdatedBucket + 192
     * @param firstAddedBucketId - the first bucket + 16 that grc was deposited to this bucket
     * @dev none of the params should overflow, since they represent weeks
     *         - it's safe to assume by 2^48 weeks climate should should have better solutions
     */
    struct BucketTracker {
        uint48 lastUpdatedBucket;
        uint48 maxBucketId;
        uint48 firstAddedBucketId;
    }

    /**
     * @dev a struct to help track the amount in weekly rewards
     * @param inheritedFromLastWeek - a flag to see if the bucket has inherited
     *             -   its vesting amount from past buckets
     * @param amountInBucket - the current amount in the bucket available as rewards
     * @param amountToDeduct - the amount to deduct from the {amountInBucket} when it initializes itself
     */
    struct WeeklyReward {
        bool inheritedFromLastWeek;
        uint256 amountInBucket;
        uint256 amountToDeduct;
    }

    //************************************************************* */
    //***************  EXTERNAL/PUBLIC VIEW FUNCTIONS  ************ */
    //************************************************************* */

    /**
     * @notice returns the current bucket
     * @return currentBucket - the current bucket
     */
    function currentBucket() public view returns (uint256) {
        return (block.timestamp - _genesisTimestamp()) / BUCKET_DURATION;
    }

    /**
     * @notice returns the bucket tracker for a given grc token
     * @return bucketTracker - the bucket tracker struct
     */
    function getBucketTracker() external view returns (BucketTracker memory) {
        return bucketTracker;
    }

    /**
     * @notice returns the weekly reward for a given bucket and grc token
     * @param id - the bucketId (week) to query for
     * @return bucket - the  weekly reward struct for the bucket
     */
    function reward(uint256 id) public view returns (WeeklyReward memory) {
        (WeeklyReward memory bucket,) = _rewardWithNeedsInitializing(id);
        return bucket;
    }

    //************************************************************* */
    //*****************  INTERNAL STATE CHANGING FUNCS  ************** */
    //************************************************************* */

    /**
     * @notice adds the grc to the current bucket
     * @dev this function is called when a user donates grc to the contract
     * @param amount - the amount of grc to add to the current bucket
     */
    function _addToCurrentBucket(uint256 amount) internal {
        //Calculate the current bucket
        uint256 currentBucketId = currentBucket();
        //The bucket to add to is always the current bucket + OFFSET_LEFT
        uint256 bucketToAddTo = currentBucketId + OFFSET_LEFT;
        //The bucket to deduct from is always the bucketToAddTo + TOTAL_VESTING_PERIODS
        uint256 bucketToDeductFrom = bucketToAddTo + TOTAL_VESTING_PERIODS;

        //The amount to add to the bucketToAddTo OR subtract from the bucketToDeductFrom
        uint256 amountToAddOrSubtract = amount / TOTAL_VESTING_PERIODS;

        //Load  bucketTracker into memory
        //Bucket trackers are used to keep track of the last updated bucket
        //and are used for caching to reduce gas costs
        BucketTracker memory _bucketTracker = bucketTracker;

        //Load the current bucket into memory
        WeeklyReward memory currentWeeklyReward = rewards[bucketToAddTo];

        //If the bucket has already reconciled with its past weeks,
        //then we can just add the amount to the bucket
        //We also deduct the amount from the bucketToDeductFrom bucket
        if (currentWeeklyReward.inheritedFromLastWeek) {
            rewards[bucketToAddTo].amountInBucket += amountToAddOrSubtract;
            rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
            return;
        }

        //Cache the last updated bucket
        //The last updated bucket is the last bucket thats {amountInBucket} was updated
        //If the last updated bucket has never been set (aka == 0),
        //then that means the first bucket to be updated is the bucketToAddTo
        //If the last updated bucket was already set, then we use that
        uint256 lastUpdatedBucket =
            _bucketTracker.lastUpdatedBucket == 0 ? bucketToAddTo : _bucketTracker.lastUpdatedBucket;
        WeeklyReward memory lastBucket = rewards[lastUpdatedBucket];

        //We already know we are going to add {amountToAddOrSubtract} to the {bucketToDeductFrom}
        rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;

        //This means that we don't need to look backwards
        //Since all the vested amount from that bucket would have been emptied by now if the bucket hadnt been refreshed in 192 weeks
        // If the lastUpdatedBucket is the current bucket, we also don't need to look backwards
        //If the {bucketToAddTo} is greater than the {maxBucketId} then we don't need to look backwards
        //This is so because if {bucketToAddTo} is > {maxBucketId} then that means that all the tokens have already vested
        //because tokens vest in between {bucketToAddTo} and {maxBucketId}
        //This would only be the case if there has been a long period of time where no one has called {claimRewards}
        //Or, no one has donated the grc to the contract
        //Also, if the last bucket is the same as the bucket to add to, then we don't need to look backwards neither
        bool pastDataIrrelavant = bucketToAddTo > _bucketTracker.maxBucketId || lastUpdatedBucket == bucketToAddTo;
        //If past data is irrelavant, we can assume that we start fresh from the current bucket
        uint256 totalToDeductFromBucket = pastDataIrrelavant ? 0 : currentWeeklyReward.amountToDeduct;

        //As such, we don't need to look backwards if the past data is irrelavant
        if (!pastDataIrrelavant) {
            //However, if the past data is relavant,
            //We start at the last bucket that was updated,
            //And we look forwards until we reach the bucketToAddTo
            for (uint256 i = lastUpdatedBucket; i < bucketToAddTo; ++i) {
                totalToDeductFromBucket += rewards[i].amountToDeduct;
            }
        }

        /**
         * We then set
         *         {
         *             amountInBucket: (lastBucket.amountInBucket + amountToAddOrSubtract) - totalToDeductFromBucket,
         *             amountToDeduct: 0,
         *             inheritedFromLastWeek: true
         *         }
         *         We know that lastBucket.amountInBucket will always have a value > 0 (if the bucket has been donated to),
         *         and we also know that every time a bucket is donated to, it becomes the last updated bucket,
         *         therefore, {lastBucket.amountInBucket} is intended to be a cumulative sum of all the donations
         *         with {totalToDeductFromBucket} being the amount that is needed to be deducted from the bucket
         *         Once we adjust the amount in the bucket, we set the {inheritedFromLastWeek} to true
         *         We also set the {amountToDeduct} to 0 since we don't need to deduct anything from the bucket anymore
         */
        rewards[bucketToAddTo] = WeeklyReward({
            inheritedFromLastWeek: true,
            amountInBucket: (lastBucket.amountInBucket + amountToAddOrSubtract) - totalToDeductFromBucket,
            amountToDeduct: 0
        });

        //If the lastUpdatedBucket has changed, then we update the lastUpdatedBucket
        if (_bucketTracker.lastUpdatedBucket != bucketToAddTo) {
            bucketTracker = BucketTracker(
                uint48(bucketToAddTo),
                uint48(bucketToAddTo + TOTAL_VESTING_PERIODS - 1),
                _bucketTracker.firstAddedBucketId
            );
        }
    }

    /**
     * @notice returns the weekly reward for a given bucket
     * @dev if the bucket has not yet been initialized,
     *             - the function will look backwards to calculate the correct amount
     *             - if the bucket has been initialized, it will return the bucket
     * @param id - the bucketId (week) to query for
     * @return bucket - the  weekly reward struct for the bucket
     * @return needsInitializing -- flag to see if the bucket needs to be initialized
     * @dev `needsInitializing` should be used in the withdraw reward function to see if the bucket needs to be initialized
     */
    function _rewardWithNeedsInitializing(uint256 id) internal view returns (WeeklyReward memory, bool) {
        WeeklyReward memory bucket = rewards[id];
        // If the bucket has already been initialized
        // Then we can just return the bucket.
        if (bucket.inheritedFromLastWeek || id < 16) {
            return (bucket, false);
        }

        // If the index to search for is greater than the maxBucketId
        // than that means all the tokens would have vested,
        // So we return the empty bucket
        BucketTracker memory _bucketTracker = bucketTracker;
        if (id > _bucketTracker.maxBucketId) {
            return (bucket, false);
        }

        uint256 amountToSubtract = bucket.amountToDeduct;
        //Can't underflow since we start at id 16
        uint256 lastBucketId = id - 1;

        //We get the first added bucket id from the bucket tracker.
        //The tracker helps us prevent uneccessary backward lookups
        uint256 firstUpdatedBucket = _bucketTracker.firstAddedBucketId;
        while (true) {
            // if the firstUpdatedbucket is greater than the last bucket id
            //then we break out of the loop
            //This happens in the case where the bucket has not been initialized yet
            //And also in the case where we re-add a grc token to the contract
            // after all its vesting periods have ended
            if (firstUpdatedBucket > lastBucketId) {
                break;
            }
            //Load the last bucket into memory
            WeeklyReward memory lastBucket = rewards[lastBucketId--];
            // add the amount to deduct from the last bucket to the amount to subtract
            amountToSubtract += lastBucket.amountToDeduct;

            //If the last bucket has inherited from the last week
            if (lastBucket.inheritedFromLastWeek) {
                //We set the amount in the bucket to the last bucket amount - the amount to subtract
                //This marks the point at which we can stop looking backwards
                //It's also important to keep in mind that this algorithm only works
                //because we know that the last bucket will always have a value
                //If it does not have a value -- that means that the bucket has not been initialized
                // and therefore there are no rewards that need to be accounted for in those buckets
                bucket.amountInBucket = lastBucket.amountInBucket - amountToSubtract;
                break;
            }
        }
        return (bucket, true);
    }

    //************************************************************* */
    //**************  INTERNAL/PRIVATE STATE CHANGING  ************ */
    //************************************************************* */

    /**
     * @dev gets the total amount of grc in a bucket that is available to withdraw and initializes it
     *             - this is a helper function only meant to be used inside the claimRewards function
     * @param id - the id of the bucket
     */
    function _getAmountForTokenAndInitIfNot(uint256 id) internal returns (uint256) {
        (WeeklyReward memory weeklyReward, bool needsInitializing) = _rewardWithNeedsInitializing(id);
        if (needsInitializing) {
            weeklyReward.inheritedFromLastWeek = true;
            rewards[id] = weeklyReward;
        }
        return weeklyReward.amountInBucket;
    }

    //************************************************************* */
    //**************  INTERNAL/PRIVATE VIEW  ************ */
    //************************************************************* */

    /// @dev this must be overriden inside the parent contract.
    function _genesisTimestamp() internal view virtual returns (uint256) {
        return 0;
    }
}
