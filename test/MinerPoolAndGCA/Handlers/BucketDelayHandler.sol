// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {MockGCA} from "@glow/MinerPoolAndGCA/mock/MockGCA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGCA} from "@glow/interfaces/IGCA.sol";
import {MockMinerPoolAndGCA} from "@glow/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";

contract BucketDelayHandler is Test {
    MockMinerPoolAndGCA public mmgca;
    uint256 private constant _ONE_WEEK = 604800;

    uint256[] private _ghost_delayedBucketIds;
    uint256[] private _ghost_nonDelayedBucketIds;

    mapping(uint256 => bool) public isDelayed;
    mapping(uint256 => bool) public isNotDelayed;

    function setMinerPool(address minerPool) external {
        if (address(mmgca) == address(0)) return;
        mmgca = MockMinerPoolAndGCA(minerPool);
    }

    function delayBucket(uint256 bucketToDelay) external {
        vm.warp(mmgca.GENESIS_TIMESTAMP() + (bucketToDelay) * _ONE_WEEK);
        mmgca.delayBucketFinalization(bucketToDelay);
        pushToDelayBuckets(bucketToDelay);
    }

    function preventBucketDelay(uint256 bucketToPreventDelay) external {
        vm.warp(mmgca.GENESIS_TIMESTAMP() + (bucketToPreventDelay) * _ONE_WEEK);
        pushToNotDelayedBuckets(bucketToPreventDelay);
    }

    function pushToDelayBuckets(uint256 bucketId) internal {
        bucketId = bound(bucketId, 0, 5000);
        if (isNotDelayed[bucketId]) revert();
        if (isDelayed[bucketId]) return;
        isDelayed[bucketId] = true;
        _ghost_delayedBucketIds.push(bucketId);
    }

    function pushToNotDelayedBuckets(uint256 bucketId) internal {
        bucketId = bound(bucketId, 0, 5000);
        if (isDelayed[bucketId]) revert();
        if (isNotDelayed[bucketId]) return;
        isNotDelayed[bucketId] = true;
        _ghost_nonDelayedBucketIds.push(bucketId);
    }

    // function warpForward(uint256 timeToWarp) public {
    //     vm.warp(block.timestamp + (timeToWarp % _ONE_WEEK) * 10);
    // }

    function delayedBucketIds() external view returns (uint256[] memory) {
        return _ghost_delayedBucketIds;
    }

    function nonDelayedBucketIds() external view returns (uint256[] memory) {
        return _ghost_nonDelayedBucketIds;
    }
}
