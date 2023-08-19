// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.21;

// import "forge-std/console.sol";

// contract MinerArray {
//     uint256 public constant OFFSET_LEFT = 16;
//     uint256 public constant OFFSET_RIGHT = 208;
//     uint256 public constant BUCKET_DURATION = uint256(7 days);
//     uint256 public constant TOTAL_VESTING_PERIODS = OFFSET_RIGHT - OFFSET_LEFT;
//     mapping(uint256 => WeeklyReward) public rewards;
//     uint256 public immutable GENESIS_TIMESTAMP;
//     uint256 public lastUpdatedBucket;

//     constructor() {
//         GENESIS_TIMESTAMP = block.timestamp;
//     }

//     struct WeeklyRewards {
//         bool initialized;
//         address[] grcTokens;
//         //Mapping for easy lookup
//         mapping(address => Reward) rewards;
//     }

//     struct Reward {
//         uint256 amountToDeduct;
//         uint256 amountInBucket; //2 slots
//         bool init;
//     }

//     function currentBucket() public view returns (uint256) {
//         return (block.timestamp - GENESIS_TIMESTAMP) / BUCKET_DURATION;
//     }

//     function addToCurrentBucket(address grcToken, uint256 amount) public {
//         uint256 currentBucketId = currentBucket();
//         uint256 bucketToAddTo = currentBucketId + OFFSET_LEFT;
//         uint256 bucketToDeductFrom = bucketToAddTo + TOTAL_VESTING_PERIODS + 1;
//         uint256 amountToAddOrSubtract = amount / TOTAL_VESTING_PERIODS;
//         uint256 _lastUpdatedBucket = lastUpdatedBucket;

//         if (currentBucketId == 0) {
//             rewards[bucketToAddTo].rewards[grcToken].amountInBucket += amountToAddOrSubtract;
//             rewards[bucketToDeductFrom].rewards[grcToken].amountToDeduct += amountToAddOrSubtract;
//             rewards[bucketToAddTo].initialized = true;

//             //Push once
//             if(!rewards[bucketToAddTo].rewards[grcToken].init) {
//                 rewards[bucketToAddTo].grcTokens.push(grcToken);
//                 rewards[bucketToDeductFrom].grcTokens.push(grcToken);
//             }
//             //push
//             if (_lastUpdatedBucket != bucketToAddTo) {
//                 lastUpdatedBucket = bucketToAddTo;
//             }
//             return;
//         }

//         WeeklyReward memory currentBucket = rewards[bucketToAddTo];
//         if (currentBucket.initialized) {
//             rewards[bucketToAddTo].amountInBucket += amountToAddOrSubtract;
//             rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
//             return;
//         }

//         WeeklyReward memory lastBucket = rewards[_lastUpdatedBucket];

//         rewards[bucketToDeductFrom].amountToDeduct += amountToAddOrSubtract;
//         uint256 totalToDeductFromBucket = currentBucket.amountToDeduct;

//         for (uint256 i = _lastUpdatedBucket; i < bucketToAddTo; ++i) {
//             totalToDeductFromBucket += rewards[i].amountToDeduct;
//         }

//         rewards[bucketToAddTo] =
//             WeeklyReward(true, (lastBucket.amountInBucket + amountToAddOrSubtract) - totalToDeductFromBucket, 0);

//         if (_lastUpdatedBucket != bucketToAddTo) {
//             lastUpdatedBucket = bucketToAddTo;
//         }
//     }

//     function minBucket(uint256 forwardBucket) private view returns (uint256) {
//         if (forwardBucket < TOTAL_VESTING_PERIODS) return OFFSET_LEFT;
//         return forwardBucket - TOTAL_VESTING_PERIODS;
//     }

//     function getRewards(uint256 start, uint256 end) public view returns (WeeklyReward[] memory) {
//         WeeklyReward[] memory _rewards = new WeeklyReward[](end - start);
//         for (uint256 i = start; i < end; i++) {
//             _rewards[i] = reward(i);
//         }
//         return _rewards;
//     }

//     function reward(uint256 id) external view returns (WeeklyReward memory) {
//         WeeklyReward memory bucket = rewards[id];
//         if (bucket.initialized || id < 16) {
//             return bucket;
//         }

//         uint256 amountToSubtract = bucket.amountInBucket;
//         uint256 lastBucketId = id - 1;
//         while (true) {
//             WeeklyReward memory lastBucket = rewards[lastBucketId--];
//             amountToSubtract += lastBucket.amountToDeduct;
//             if (lastBucket.initialized) {
//                 bucket.amountInBucket = lastBucket.amountInBucket - amountToSubtract;
//                 break;
//             }
//         }
//         return bucket;
//     }

//     function _containsElement(address[] calldata array, address element)
//         private
//         pure
//         returns (bool isContained, uint256 indexIfContained)
//     {
//         unchecked {
//             for (uint256 i; i < array.length; ++i) {
//                 if (array[i] == element) {
//                     return (true, i);
//                 }
//             }
//             return (false, type(uint256).max);
//         }
//     }
// }
