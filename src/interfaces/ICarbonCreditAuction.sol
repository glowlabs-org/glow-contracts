// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICarbonCreditAuction {
    /* -------------------------------------------------------------------------- */
    /*                                   state-changing                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice receives GCC from the miner pool
     * @param amount the amount of GCC to receive
     * @dev this function can only be called by the miner pool contract
     */
    function receiveGCC(uint256 amount) external;
    /**
     * @notice purchases {unitsToBuy} units of GCC at a maximum price of {maxPricePerUnit} GLOW per unit
     * @param unitsToBuy the number of units to buy
     * @param maxPricePerUnit the maximum price per unit that the user is willing to pay
     */
    function buyGCC(uint256 unitsToBuy, uint256 maxPricePerUnit) external;

    /* -------------------------------------------------------------------------- */
    /*                                 view functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice returns the price per unit of GCC
     */
    function getPricePerUnit() external view returns (uint256);

    /**
     * @notice returns the total supply of GCC available for sale in WEI
     * @dev this is not to be confused with the total units of GCC available for sale
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice returns the number of units of GCC available for sale
     */
    function unitsForSale() external view returns (uint256);

    /**
     * @notice returns the cumulative total number of units of GCC that have been sold or are available for sale
     */
    function totalSaleUnits() external view returns (uint256);
}
