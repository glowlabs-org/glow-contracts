// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../GLOW.sol";

contract TestGLOW is Glow {
    constructor(address _earlyLiquidityAddress, address _vestingContract)
        Glow(_earlyLiquidityAddress, _vestingContract)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
