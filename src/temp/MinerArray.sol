// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.21;

// import "forge-std/console.sol";

// //TODO: switch this to be less complex and have people post the addresses of the grc tokens
// contract MinerArray {
//     uint256 public constant OFFSET_LEFT = 16;
//     uint256 public constant OFFSET_RIGHT = 208;
//     uint256 public constant BUCKET_DURATION = uint256(7 days);
//     uint256 public constant TOTAL_VESTING_PERIODS = OFFSET_RIGHT - OFFSET_LEFT;
//     mapping(uint256 => WeeklyRewards) public rewards;
//     uint256 public immutable GENESIS_TIMESTAMP;
//     uint256 public lastUpdatedBucket;

//     constructor() {
//         GENESIS_TIMESTAMP = block.timestamp;
//     }

//     struct WeeklyRewards {
//         bool initialized;
//         address[] grcTokens;
//         // Mapping for easy lookup
//         mapping(address => Reward) rewards;
//     }

//     struct Reward {
//         uint256 amountToDeduct;
//         uint256 amountInBucket; //2 slots
//         bool initialized;
//         bool pushed;
//     }

//     function currentBucket() public view returns (uint256) {
//         return (block.timestamp - GENESIS_TIMESTAMP) / BUCKET_DURATION;
//     }

//     struct IHelper {
//         address token;
//         uint amountToDeduct;
//         uint amountToAdd;
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

//             //Push once to both buckets
//             if (!rewards[bucketToAddTo].rewards[grcToken].pushed) {
//                 rewards[bucketToAddTo].grcTokens.push(grcToken);
//                 rewards[bucketToAddTo].rewards[grcToken].pushed = true;
//                 rewards[bucketToDeductFrom].grcTokens.push(grcToken);
//                 rewards[bucketToDeductFrom].rewards[grcToken].pushed = true;

//             }
//             //push
//             if (_lastUpdatedBucket != bucketToAddTo) {
//                 lastUpdatedBucket = bucketToAddTo;
//             }
//             return;
//         }

//         /*
//             If the bucket is already initialized
//             that means that we've succesfully imported all the past tokens and
//             added the correct amounts and pushed to the array and set ```pushed in the mapping to true```
//         */

//         WeeklyRewards storage currentBucket = rewards[bucketToAddTo];
//         if (currentBucket.initialized) {
//             rewards[bucketToAddTo].rewards[grcToken].amountInBucket += amountToAddOrSubtract;
//             rewards[bucketToDeductFrom].rewards[grcToken].amountToDeduct += amountToAddOrSubtract;
//             return;
//         }

//         //If the bucket is not initialized
//         IHelper[] memory helpers = new IHelper[](10);
//         uint timesPushedToHelpers;
//         for(uint i = _lastUpdatedBucket; i<bucketToAddTo;++i){
//             WeeklyRewards storage lastBucket = rewards[_lastUpdatedBucket];
//             address[] memory lastBucketGrcTokens = lastBucket.grcTokens;
//             for(uint j; j<lastBucketGrcTokens.length;++j){
//                 address token = lastBucketGrcTokens[j];
//                 uint totalToAdd = lastBucket.rewards[token].amountInBucket;
//                 uint totalToDeduct = lastBucket.rewards[token].amountToDeduct;
//                 //+1 so we can loop
//                 for(uint k; k<timesPushedToHelpers+1;++k){
//                     if(k == timesPushedToHelpers) {
//                         helpers[k] = IHelper(token,totalToAdd,totalToDeduct);
//                         ++timesPushedToHelpers;
//                         break;
//                     }
//                     //if we reach here, it means we didnt push
//                     if(token == helpers[k].token) {
//                         //Todo: we probably dont need this since only
//                         // the last updated bucket will have the numbers.
//                         helpers[k].amountToAdd += totalToAdd;
//                         helpers[k].amountToDeduct += totalToDeduct;
//                     }
//                 }
//             }
//         }

//         // assembly ("memory-safe") {
//         //     //Resize helpers,
//         //     mstore(helpers,timesPushedToHelpers)
//         // }

//         for(uint i; i<timesPushedToHelpers+1;++i) {
//             IHelper memory helper = helpers[i];
//             currentBucket.rewards[helper.token] = Reward(
//                 0,
//                 helper.totalToAdd + amountToAddOrSubtract - helper.amountToDeduct,
//                 true,
//                 true
//             );

//         }
//         currentBucket.initialized = true;

//         if (_lastUpdatedBucket != bucketToAddTo) {
//             lastUpdatedBucket = bucketToAddTo;
//         }
//     }

//     function minBucket(uint256 forwardBucket) private view returns (uint256) {
//         if (forwardBucket < TOTAL_VESTING_PERIODS) return OFFSET_LEFT;
//         return forwardBucket - TOTAL_VESTING_PERIODS;
//     }

//     // function getRewards(uint256 start, uint256 end) public view returns (IHelper[] memory) {
//     //     WeeklyRewards[] memory _rewards = new WeeklyRewards[](end - start);
//     //     for (uint256 i = start; i < end; i++) {
//     //         _rewards[i] = reward(i);
//     //     }
//     //     return _rewards;
//     // }

//     // function reward(uint256 id) public view returns (IHelper memory) {
//     //     WeeklyRewards storage bucket = rewards[id];
//     //     if (bucket.initialized || id < 16) {
//     //         return bucket;
//     //     }

//     //     uint256 amountToSubtract = bucket.amountInBucket;
//     //     uint256 lastBucketId = id - 1;
//     //     while (true) {
//     //         WeeklyRewards memory lastBucket = rewards[lastBucketId--];
//     //         amountToSubtract += lastBucket.amountToDeduct;
//     //         if (lastBucket.initialized) {
//     //             bucket.amountInBucket = lastBucket.amountInBucket - amountToSubtract;
//     //             break;
//     //         }
//     //     }
//     //     return bucket;
//     // }

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
