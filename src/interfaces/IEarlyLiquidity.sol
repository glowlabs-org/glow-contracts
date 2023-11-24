// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEarlyLiquidity {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                  */
    /* -------------------------------------------------------------------------- */
    error PriceTooHigh();
    error ModNotZero();
    error AllSold();
    error MinerPoolAlreadySet();
    error ZeroAddress();
    error TooManyIncrements();

    /* -------------------------------------------------------------------------- */
    /*                                   events                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice emitted when a purchase is made
     * @param buyer The address of the buyer
     * @param glwReceived The amount of glow the buyer received
     * @param totalUSDCSpent The total amount of USDC the buyer spent to buy the tokens
     * @dev emitted when {buy} is successfully called
     */

    event Purchase(address indexed buyer, uint256 glwReceived, uint256 totalUSDCSpent);

    /**
     * @notice Buys tokens with USDC
     * @param increments The amount of increments to buy
     *             - an {increment} is .01 GLW
     * @param maxCost The maximum cost to pay for all the increments
     */
    function buy(uint256 increments, uint256 maxCost) external;

    /**
     * @notice Calculates the price of a given amount of tokens
     * @param increments The amount of increments to buy
     * @return price - the total price in USDC for the given amount of increments
     */
    function getPrice(uint256 increments) external view returns (uint256);

    /**
     * @notice Returns the total amount of GLW tokens sold so far
     * @return totalSold - total amount of GLW tokens sold so far (18 decimal value)
     */
    function totalSold() external view returns (uint256);

    /**
     * @notice Returns the current price of the next token.
     * @return currentPrice current price of the next token in microdollars
     */
    function getCurrentPrice() external view returns (uint256);
}
