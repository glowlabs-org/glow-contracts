// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../GuardedLaunch/Glow.GuardedLaunch.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";

contract GoerliGlowGuardedLaunch is GlowGuardedLaunch {
    constructor(
        address _earlyLiquidityAddress,
        address _vestingContract,
        address _gcaAndMinerPoolAddress,
        address _vetoCouncilAddress,
        address _grantsTreasuryAddress,
        address _owner,
        address _usdg,
        address _uniswapV2Factory
    )
        GlowGuardedLaunch(
            _earlyLiquidityAddress,
            _vestingContract,
            _gcaAndMinerPoolAddress,
            _vetoCouncilAddress,
            _grantsTreasuryAddress,
            _owner,
            _usdg,
            _uniswapV2Factory
        )
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getPair(address factory, address _tokenA, address _tokenB)
        internal
        view
        virtual
        override
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        pair = UniswapV2Library.pairFor(factory, token0, token1);
        return pair;
    }
}
