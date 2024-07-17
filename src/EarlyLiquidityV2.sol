
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {MinerPoolAndGCAV2} from "@/MinerPoolAndGCA/MinerPoolAndGCAV2.sol";

contract EarlyLiquidityV2 is EarlyLiquidity {
    constructor(
        address _usdcAddress,
        address _holdingContract,
        address _glowToken,
        address _minerPoolAddress,
        uint256 _totalIncrementsSoldInV1
    ) EarlyLiquidity(_usdcAddress, _holdingContract, _glowToken, _minerPoolAddress) {
        _totalIncrementsSold = _totalIncrementsSoldInV1;
    }

    function _handleRegisterPurchaseToMinerPool(uint256 amount) internal virtual override {
        MinerPoolAndGCAV2(address(MINER_POOL)).donateToUSDCMinerRewardsPoolEarlyLiquidity(address(USDC_TOKEN), amount);
    }
}
