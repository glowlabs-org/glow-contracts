// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../GCC.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";

contract TestGCC is GCC {
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glow,
        address _usdc,
        address _uniswapV2Router
    ) GCC(_gcaAndMinerPoolContract, _governance, _glow, _usdc, _uniswapV2Router) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getPair(address factory, address _usdc) internal view virtual override returns (address pair) {
        (address token0, address token1) = sortTokens(address(this), _usdc);
        pair = UnifapV2Library.pairFor(factory, token0, token1);
        return pair;
    }
}
