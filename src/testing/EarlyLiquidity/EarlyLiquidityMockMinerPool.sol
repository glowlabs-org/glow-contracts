// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

contract EarlyLiquidityMockMinerPool is MinerPoolAndGCA {
    address[] private _startingGCAs;
    uint256 public grcDepositFromEarlyLiquidity;

    constructor(address _earlyLiquidity, address _glowAddress, address _grcToken, address _holdingContract)
        MinerPoolAndGCA(
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
    /**
     * @inheritdoc MinerPoolAndGCA
     */

    function donateToUSDCMinerRewardsPool(uint256 amount) external virtual override {
        return;
    }

    /**
     * @inheritdoc MinerPoolAndGCA
     */
    function donateToUSDCMinerRewardsPoolEarlyLiquidity(uint256 amount) external virtual override {
        if (msg.sender != this.earlyLiquidity()) {
            _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        }

        grcDepositFromEarlyLiquidity += amount;
    }
}
