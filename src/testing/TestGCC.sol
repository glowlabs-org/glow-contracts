// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../GCC.sol";

contract TestGCC is GCC {
    constructor(address _carbonCreditAuction, address _gcaAndMinerPoolContract, address _governance)
        GCC(_carbonCreditAuction, _gcaAndMinerPoolContract, _governance)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
