// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../GLOW.sol";

contract TestGLOW is Glow {
    /**
     * @notice constructs a new GLOW token
     * @param _earlyLiquidityAddress the address to send the early liquidity to
     * @param _vestingContract the address of the vesting contract
     */
    constructor(address _earlyLiquidityAddress, address _vestingContract)
        Glow(_earlyLiquidityAddress, _vestingContract)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
