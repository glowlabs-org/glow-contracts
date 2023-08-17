// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";

contract MinerDistributionMath {

    uint constant OFFSET_LEFT = 16;
    uint constant OFFSET_RIGHT = 208;
    uint constant BUCKET_DURATION = uint(7 days);
    uint256 constant TOTAL_VESTING_PERIODS = OFFSET_RIGHT - OFFSET_LEFT;
    mapping(uint => WeeklyReward) public rewards;
    uint256 public immutable GENESIS_TIMESTAMP;
    
    
    constructor() {
        GENESIS_TIMESTAMP = block.timestamp;
    }

    struct WeeklyReward {
        bool inheritedFromLastWeek;
        uint amountInBucket;
        uint amountToDeduct;
    }

    function currentBucket() public view returns(uint) {
        return (block.timestamp - GENESIS_TIMESTAMP) / BUCKET_DURATION;
    }

    function addToCurrentBucket(uint amount) public {
        uint currentBucket = currentBucket();
        uint bucketToAddTo = currentBucket + OFFSET_LEFT;
        uint bucketToDeductFrom = currentBucket + OFFSET_RIGHT + 1;
        uint amountToAddOrSubtract = amount / TOTAL_VESTING_PERIODS;
        if(currentBucket == 0) {
            rewards[bucketToAddTo].amountInBucket += amountToAddOrSubtract;
            rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
            rewards[bucketToAddTo].inheritedFromLastWeek = true;
            return;
        }
        
        WeeklyReward memory reward = rewards[bucketToAddTo];
        if(reward.inheritedFromLastWeek) {
            rewards[bucketToAddTo].amountInBucket += amountToAddOrSubtract;
            rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
            return;
        }
        
        uint startingIndex = bucketToAddTo - 1;
        uint amountToDeductFromLastBucket;
        uint amountToAddFromLastBucket;
        uint minBucket = minBucket(currentBucket);
        while (startingIndex >= minBucket) {
            if(startingIndex == OFFSET_LEFT)  {
                 rewards[bucketToAddTo] = WeeklyReward(true, amountToAddOrSubtract, 0);
                rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
                return;
            }
            WeeklyReward storage lastBucket = rewards[startingIndex--];
            if(lastBucket.inheritedFromLastWeek) {
                amountToAddFromLastBucket = lastBucket.amountToDeduct;
                amountToAddFromLastBucket = lastBucket.amountInBucket;
                break;
            }
        }
        //We've already deducted
        uint startingRate =  amountToAddFromLastBucket + amountToAddOrSubtract -  amountToDeductFromLastBucket;
        rewards[bucketToAddTo] = WeeklyReward(true, startingRate, 0);
        rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
    
    }

    
    function minBucket(uint forwardBucket) private view returns(uint) {
        if(forwardBucket < TOTAL_VESTING_PERIODS) return OFFSET_LEFT;
        return forwardBucket - TOTAL_VESTING_PERIODS;
    }

    function getRewards(uint start,uint end) public view returns(WeeklyReward[] memory) {
        WeeklyReward[] memory _rewards = new WeeklyReward[](end - start);
        for(uint i = start; i < end; i++) {
            _rewards[i] = rewards[i];
        }
        return _rewards;
    }


    // function reward(uint id) public view returns(WeeklyReward memory) {
    //     return rewards[id];
    // }
    
    function reward(uint id) public view returns(WeeklyReward memory) {
        WeeklyReward memory bucket = rewards[id];
        return bucket;
    }
    //     if(bucket.inheritedFromLastWeek) return bucket;
    //     if(id == 0) return rewards[0];
    //     uint startingIndex = id - 1;
    //     uint amountToSubtractFromRewards;
    //     uint amountToAddToRewards;

    //     bool log;
    //     if(id == 36) {
    //         log = true;
    //     }
    //     uint firstLookbackTrueId;
    //     while(startingIndex >= OFFSET_LEFT) {
    //         //...
    //         if(startingIndex == 0) break;
    //         WeeklyReward memory lastBucket = rewards[startingIndex--];
    //         amountToAddToRewards += lastBucket.amountInBucket;
    //         amountToSubtractFromRewards += bucket.amountToDeduct;
    //         if(amountToAddToReward)
    //         if(lastBucket.inheritedFromLastWeek) {
    //             uint firstLookbackTrueId;
    //         }
    //     }
    

    //     bucket.amountInBucket += amountToAddToRewards - amountToSubtractFromRewards;
    //     return bucket;
    // }
    
}