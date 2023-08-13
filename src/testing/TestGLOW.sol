// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../GLOW.sol";

contract TestGLOW is Glow {
    constructor(address _earlyLiquidityAddress) Glow(_earlyLiquidityAddress) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
