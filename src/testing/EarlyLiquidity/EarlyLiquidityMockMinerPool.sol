// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

contract EarlyLiquidityMockMinerPool is MinerPoolAndGCA {
    address[] private _startingGCAs;
    mapping(address => uint256) public grcDepositFromEarlyLiquidity;

    constructor(address _earlyLiquidity, address _glowAddress)
        MinerPoolAndGCA(_startingGCAs, _glowAddress, address(0), bytes32(0x0), _earlyLiquidity)
    {}
    /**
     * @inheritdoc MinerPoolAndGCA
     */

    function donateToGRCMinerRewardsPool(address grcToken, uint256 amount) external virtual override {
        return;
    }

    /**
     * @inheritdoc MinerPoolAndGCA
     */
    function donateToGRCMinerRewardsPoolEarlyLiquidity(address grcToken, uint256 amount) external virtual override {
        if (msg.sender != this.earlyLiquidity()) {
            _revert(IMinerPool.CallerNotEarlyLiquidity.selector);
        }

        grcDepositFromEarlyLiquidity[grcToken] += amount;
    }
}