// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@/GCC.sol";

contract MainnetForkTestGCC is GCC {
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
}
