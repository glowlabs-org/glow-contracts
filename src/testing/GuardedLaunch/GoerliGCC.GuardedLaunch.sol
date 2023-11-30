// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./TestGCC.GuardedLaunch.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";

contract GoerliGCCGuardedLaunch is TestGCCGuardedLaunch {
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glowToken,
        address _usdg,
        address _vetoCouncilAddress,
        address _uniswapRouter,
        address _uniswapFactory
    )
        TestGCCGuardedLaunch(
            _gcaAndMinerPoolContract,
            _governance,
            _glowToken,
            _usdg,
            _vetoCouncilAddress,
            _uniswapRouter,
            _uniswapFactory
        )
    {}

    function getPair(address factory, address _tokenB) internal view override returns (address) {
        return UniswapV2Library.pairFor(factory, address(this), _tokenB);
    }
}
