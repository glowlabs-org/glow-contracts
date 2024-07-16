// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MinerPoolAndGCAV2} from "@/MinerPoolAndGCA/MinerPoolAndGCAV2.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

contract EarlyLiquidityMockMinerPoolV2 is MinerPoolAndGCAV2 {
    address[] private _startingGCAs;
    uint256 public grcDepositFromEarlyLiquidity;

    constructor(address _earlyLiquidity, address _glowAddress, address _grcToken, address _holdingContract)
        MinerPoolAndGCAV2(
            _startingGCAs,
            _glowAddress,
            address(0),
            bytes32(0x0),
            _earlyLiquidity,
            _grcToken,
            //Veto Council Contract
            address(0x4444),
            _holdingContract,
            address(0xfffffffffaa3141241) // gcc
        )
    {}

    function donateToUSDCMinerRewardsPool(address token, uint256 amount) external virtual override {
        return;
    }

    function donateToUSDCMinerRewardsPoolEarlyLiquidity(address token, uint256 amount) external virtual override {
        if (msg.sender != this.earlyLiquidity()) {
            _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        }

        grcDepositFromEarlyLiquidity += amount;
    }
}
