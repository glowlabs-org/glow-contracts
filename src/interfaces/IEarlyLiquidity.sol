// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IEarlyLiquidity {
    error PriceTooHigh();
    error ModNotZero();

    /**
     * @notice Buys tokens with USDC
     * @param amount The amount of tokens to buy (including decimals)
     * @param maxCost The maximum cost to pay for the tokens
     */
    function buy(uint256 amount, uint256 maxCost) external;

    /**
     * @notice Calculates the price of a given amount of tokens
     * @param amount The amount of tokens to buy
     * @return The price of the tokens in microdollars
     * @dev uses the integral of 2 * .6^((total_sold + tokens_to_buy)/ 1_000_000)
     *             - to approximate the price of the tokens using calculus
     */
    function getPrice(uint256 amount) external view returns (uint256);

    /**
     * @notice Returns the total amount of tokens sold so far
     * @return The total amount of tokens sold so far including decimals
     */
    function totalSold() external view returns (uint256);

    /**
     * @notice Returns the current price of the next token.
     * @return The current price of the next token in microdollars
     */
    function getCurrentPrice() external view returns (uint256);

    event Purchase(address indexed buyer, uint256 glwReceived, uint256 totalUSDCSpent);
}
