// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {MD2} from "@/temp/MD2.sol";

contract MD2Handler is Test {
    /// @dev - we store the "should be" amounts in a ghost mapping
    mapping(uint256 => mapping(address => uint256)) public ghost_amountInBucket;

    /// @dev - we keep track of which ids have already been pushed to the ghost array
    ///         -   in order to avoid duplicates
    mapping(uint256 => mapping(address => bool)) private _pushedToBucket;

    /// @dev - the fmaous bucket ids that we will iterate over in the invariant test
    mapping(address => uint256[]) public ghost_bucketIds;

    mapping(address => uint256) public totalDeposited;

    /// @dev - the reference contract that we are testing
    MD2 public minerMath;

    address[] public grcTokens;

    uint256 public timesCalled;

    //-----------------CONSTRUCTOR-----------------

    /**
     * @notice - we pass in the address of the reference contract
     * @param _minerMath - the address of the reference contract
     * @param _grcTokens - the grc tokens to use
     */
    constructor(address _minerMath, address[] memory _grcTokens) public {
        minerMath = MD2(_minerMath);
        grcTokens = _grcTokens;
    }

    /**
     * @dev we add a reward to the current bucket,
     *         -   and then warp an amount of days forward (max 200 from fuzzer)
     *         -   we store the "should be" amounts in a ghost mapping
     *         -   and push the ids to a ghost array
     *         -   in the invariant test, we ensure that the gas optimized math matches the ghost mapping
     */
    function addRewardsToBucket(uint256 daysToWarp, uint256 amount) public {
        address grcToken = grcTokens[timesCalled++ % grcTokens.length];
        addRewardsToBucketWithToken(grcToken, daysToWarp, amount);
    }

    function addRewardsToBucketWithToken(address grcToken, uint256 daysToWarp, uint256 amount) public {
        // vm.assume(daysToWarp < 200);
        // vm.assume(amount < 1_000_000_000_000 ether);
        // amount = bound(amount, 0,1_000_000_000_000 ether);
        // daysToWarp = bound(daysToWarp, 0,200);
        amount = amount % 1_000_000_000_000 ether;
        if (minerMath.currentBucket() > type(uint48).max) return;

        //200 weeks max advance
        daysToWarp = daysToWarp % (200 * 7);
        uint256 bucketId = minerMath.currentBucket();
        uint256 offsetLeft = minerMath.OFFSET_LEFT();
        uint256 bucketToPushTo = bucketId + offsetLeft;
        uint256 totalVestingPeriods = minerMath.TOTAL_VESTING_PERIODS();
        uint256 amountToIncrementBucketBy = amount / totalVestingPeriods;
        totalDeposited[grcToken] += amountToIncrementBucketBy * totalVestingPeriods;
        for (uint256 i; i < totalVestingPeriods; i++) {
            uint256 index = bucketToPushTo + i;
            ghost_amountInBucket[index][grcToken] += amountToIncrementBucketBy;
            if (!_pushedToBucket[index][grcToken]) {
                _pushedToBucket[index][grcToken] = true;
                ghost_bucketIds[grcToken].push(index);
            }
        }
        minerMath.addToCurrentBucket(grcToken, amount);
        vm.warp(block.timestamp + daysToWarp * uint256(1 days));
    }

    /**
     * @dev same as above but does not warp forward
     *         -   this mimics the behavior of the miner pool
     *             -   where GRC can be deposited multiple times in the same bucket
     */
    function addRewardsToBucketNoWarp(uint256 amount) public {
        // vm.assume(amount < 1_000_000_000_000 ether);
        // amount = bound(amount, 0,1_000_000_000_000 ether);
        uint256 currentBucket = minerMath.currentBucket();
        if (currentBucket > type(uint48).max) return;
        amount = amount % 1_000_000_000_000 ether;

        //Round robin the grc tokens
        address grcToken = grcTokens[timesCalled++ % grcTokens.length];
        uint256 bucketId = minerMath.currentBucket();
        uint256 offsetLeft = minerMath.OFFSET_LEFT();
        uint256 bucketToPushTo = bucketId + offsetLeft;
        uint256 totalVestingPeriods = minerMath.TOTAL_VESTING_PERIODS();
        uint256 amountToIncrementBucketBy = amount / totalVestingPeriods;
        totalDeposited[grcToken] += amountToIncrementBucketBy * totalVestingPeriods;

        for (uint256 i; i < totalVestingPeriods; i++) {
            uint256 index = bucketToPushTo + i;
            ghost_amountInBucket[index][grcToken] += amountToIncrementBucketBy;
            if (!_pushedToBucket[index][grcToken]) {
                _pushedToBucket[index][grcToken] = true;
                ghost_bucketIds[grcToken].push(index);
            }
        }

        minerMath.addToCurrentBucket(grcToken, amount);
    }

    /// @dev - helper function to get all the bucket ids
    ///      - so we can iterate over them in the invariant test
    function allGhostBucketIds(address grcToken) public view returns (uint256[] memory) {
        return ghost_bucketIds[grcToken];
    }
}
