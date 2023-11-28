// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {USDG} from "@/USDG.sol";
import {UnifapV2Library} from "@unifapv2/libraries/UnifapV2Library.sol";

contract TestUSDG is USDG {
    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param _usdc the USDC token
     * @param _usdcReceiver the address to receive USDC from the `swap` function
     * @param _owner the owner of the contract
     * @param _univ2Factory the uniswap v2 factory
     */
    constructor(address _usdc, address _usdcReceiver, address _owner, address _univ2Factory)
        USDG(_usdc, _usdcReceiver, _owner, _univ2Factory)
    {}

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getPair(address factory, address _tokenA, address _tokenB) internal view override returns (address pair) {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        pair = UnifapV2Library.pairFor(factory, token0, token1);
        return pair;
    }

    function addAllowlistedContract(address _address) external {
        allowlistedContracts[_address] = true;
    }
}
