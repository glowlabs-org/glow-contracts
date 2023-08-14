// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IGovernance {
    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */
    function grantNominations(address to, uint256 amount) external;
}
