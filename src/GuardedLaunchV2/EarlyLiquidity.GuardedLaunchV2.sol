// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EarlyLiquidityV2} from "@/EarlyLiquidityV2.sol";

contract EarlyLiquidityGuardedLaunchV2 is EarlyLiquidityV2 {
    constructor(
        address _usdcAddress,
        address _holdingContract,
        address _glowToken,
        address _minerPoolAddress,
        uint256 _totalIncrementsSoldInV1
    ) EarlyLiquidityV2(_usdcAddress, _holdingContract, _glowToken, _minerPoolAddress, _totalIncrementsSoldInV1) {}
}
