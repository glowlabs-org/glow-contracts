// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../GCC.sol";

contract TestGCC is GCC {
    constructor(address _gcaAndMinerPoolContract, address _governance, address _glow)
        GCC(_gcaAndMinerPoolContract, _governance, _glow)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
