// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {MinerDistributionMath} from "@/temp/MinerDistributionMath.sol";

contract MinerDistributionHandler is Test {
    /// @dev - we store the "should be" amounts in a ghost mapping
    mapping(uint256 => uint256) public ghost_amountInBucket;

    /// @dev - we keep track of which ids have already been pushed to the ghost array
    ///         -   in order to avoid duplicates
    mapping(uint256 => bool) private _pushedToBucket;

    /// @dev - the fmaous bucket ids that we will iterate over in the invariant test
    uint256[] public ghost_bucketIds;

    /// @dev - the reference contract that we are testing
    MinerDistributionMath public minerMath;

    //-----------------CONSTRUCTOR-----------------

    /**
     * @notice - we pass in the address of the reference contract
     * @param _minerMath - the address of the reference contract
     */
    constructor(address _minerMath) public {
        minerMath = MinerDistributionMath(_minerMath);
    }

    /**
     * @dev we add a reward to the current bucket,
     *         -   and then warp an amount of days forward (max 200 from fuzzer)
     *         -   we store the "should be" amounts in a ghost mapping
     *         -   and push the ids to a ghost array
     *         -   in the invariant test, we ensure that the gas optimized math matches the ghost mapping
     */
    function addRewardsToBucket(uint256 daysToWarp, uint256 amount) public {
        vm.assume(daysToWarp < 200);
        vm.assume(amount < 1_000_000_000_000 ether);
        uint256 bucketId = minerMath.currentBucket();
        uint256 offsetLeft = minerMath.OFFSET_LEFT();
        uint256 bucketToPushTo = bucketId + offsetLeft;
        uint256 totalVestingPeriods = minerMath.TOTAL_VESTING_PERIODS();
        uint256 amountToIncrementBucketBy = amount / totalVestingPeriods;
        for (uint256 i; i < totalVestingPeriods; i++) {
            uint256 index = bucketToPushTo + i;
            ghost_amountInBucket[index] += amountToIncrementBucketBy;
            if (!_pushedToBucket[index]) {
                _pushedToBucket[index] = true;
                ghost_bucketIds.push(bucketToPushTo);
            }
        }
        minerMath.addToCurrentBucket(amount);
        vm.warp(block.timestamp + daysToWarp * uint256(1 days));
    }

    /**
     * @dev same as above but does not warp forward
     *         -   this mimics the behavior of the miner pool
     *             -   where GRC can be deposited multiple times in the same bucket
     */
    function addRewardsToBucketNoWarp(uint256 amount) public {
        vm.assume(amount < 1_000_000_000_000 ether);
        uint256 bucketId = minerMath.currentBucket();
        uint256 offsetLeft = minerMath.OFFSET_LEFT();
        uint256 bucketToPushTo = bucketId + offsetLeft;
        uint256 totalVestingPeriods = minerMath.TOTAL_VESTING_PERIODS();
        uint256 amountToIncrementBucketBy = amount / totalVestingPeriods;

        for (uint256 i; i < totalVestingPeriods; i++) {
            uint256 index = bucketToPushTo + i;
            ghost_amountInBucket[index] += amountToIncrementBucketBy;
            if (!_pushedToBucket[index]) {
                _pushedToBucket[index] = true;
                ghost_bucketIds.push(bucketToPushTo);
            }
        }
        minerMath.addToCurrentBucket(amount);
    }

    /// @dev - helper function to get all the bucket ids
    ///      - so we can iterate over them in the invariant test
    function allGhostBucketIds() public view returns (uint256[] memory) {
        return ghost_bucketIds;
    }
}
