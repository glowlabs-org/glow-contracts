// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICarbonCreditAuction {
    /**
     * @notice allows the carbon credit auction contract to receive GCC
     * @param amount the amount of GCC to receive
     * @dev should only be callable by the GCC contract
     */
    function receiveGCC(uint256 amount) external;
}
