// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GLOW.sol";

contract TestGLOW is Glow {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
