// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import "forge-std/console.sol";

interface IDecimals {
    error IncorrectDecimals();

    function decimals() external view returns (uint8);
}

//TODO: Add tests, add integral to docs, finish fulfill partial order and talk through that with david
// add deposit functions so we can deposit to GRC and Miner Pool once those contracts are up and running

/**
    * @title EarlyLiquidity
    * @author @0xSimon
    * @author @DavidVorick
    * @notice This contract allows users to buy Glow tokens with USDC
    * @dev the cost of glow rises exponentially with the amount of glow sold
        -  The price at token t = 0.6 * 2^((total_sold + t)/ 1_000_000)
    * @dev to calculate the price for x tokens in real time, we use integral calculus 
*/

contract EarlyLiquidity {
    using ABDKMath64x64 for int256;

    /// @dev The Glow token
    IERC20 public glowToken;

    /// @dev The USDC token
    IERC20 public immutable USDC_TOKEN;

    /// @dev The number of decimals for USDC
    uint256 public constant USDC_DECIMALS = 6;

    /// @dev The number 0.6 in microdollars with respect to USDC_DECIMALS
    uint256 _POINT6 = 6 * (10 ** (USDC_DECIMALS - 1));

    /// @dev The minimum increment that tokens can be bought in
    /// @dev this is essential so our floating point math doesn't break
    uint256 public constant MIN_TOKEN_INCREMENT = 1e18;

    /// @dev tokens are demagnified by 1e18 to make floating point math easier
    /// @dev the {totalSold} function returns the total sold in 1e18 (GLW DECIMALS)
    uint256 private _totalSoldDiv1e18;

    //-----------------CONSTRUCTOR-----------------

    /**
     * @notice Constructs the EarlyLiquidity contract
     * @param _usdcAddress The address of the USDC token
     * @dev does not take in Glow token since it is not deployed yet
     */
    constructor(address _usdcAddress) {
        USDC_TOKEN = IERC20(_usdcAddress);
        uint256 decimals = uint256(IDecimals(_usdcAddress).decimals());
        if (decimals != USDC_DECIMALS) {
            _revert(IDecimals.IncorrectDecimals.selector);
        }
    }

    /**
     * @notice Buys tokens with USDC
     * @param amount The amount of tokens to buy (including decimals)
     * @param maxPrice The maximum price to pay for the tokens
     */
    function buy(uint256 amount, uint256 maxPrice) external {
        //TODO: decide if we want fulfillPartialOrder
        if (amount % MIN_TOKEN_INCREMENT != 0) {
            _revert(IEarlyLiquidity.ModNotZero.selector);
        }
        amount = amount / MIN_TOKEN_INCREMENT;
        uint256 totalCost = getPrice(amount);
        uint256 price = totalCost / amount;
        if (price > maxPrice) {
            // if (!fulfillPartialOrder) {
            _revert(IEarlyLiquidity.PriceTooHigh.selector);
            // }
            // price = maxPrice;
            // amount = getAmountFromDesiredPrice(_totalSoldDiv1e18, maxPrice);
        }
        SafeERC20.safeTransferFrom(USDC_TOKEN, msg.sender, address(this), totalCost);
        SafeERC20.safeTransfer(glowToken, msg.sender, amount * 1e18);
        _totalSoldDiv1e18 += amount;
        return;
    }

    /**
     * @notice Calculates the price of a given amount of tokens
     * @param amount The amount of tokens to buy
     * @return The price of the tokens in microdollars
     * @dev uses the integral of 2 * .6^((total_sold + tokens_to_buy)/ 1_000_000)
     *             - to approximate the price of the tokens using calculus
     */
    function getPrice(uint256 amount) public view returns (uint256) {
        return _getPrice(_totalSoldDiv1e18, amount);
    }

    /**
     * @notice Returns the total amount of tokens sold so far
     * @return The total amount of tokens sold so far including decimals
     */

    //-----------------GETTERS-----------------
    function totalSold() public view returns (uint256) {
        return _totalSoldDiv1e18 * 1e18;
    }

    /**
     * @notice Returns the current price of the tokens
     * @return The current price of the tokens in microdollars
     */
    function getCurrentPrice() external view returns (uint256) {
        return _getPrice(_totalSoldDiv1e18, 1);
    }

    //-----------------SETTERS-----------------
    /**
     * @notice Sets the glow token address
     * @param _glowToken The address of the glow token
     * @dev Can only be called once
     */
    function setGlowToken(address _glowToken) external {
        require(address(glowToken) == address(0), "Glow token already set");
        glowToken = IERC20(_glowToken);
    }

    //-----------------TOKEN MATH-----------------

    /**
     * @notice Calculates the price of a given amount of tokens
     * @param totalSold The total amount of tokens sold so far
     * @param tokensToBuy The amount of tokens to buy
     * @return The price of the tokens in microdollars
     * @dev uses the integral of 2 * .6^((total_sold + tokens_to_buy)/ 1_000_000)
     *             - to approximate the price of the tokens using calculus
     */
    function _getPrice(uint256 totalSold, uint256 tokensToBuy) private view returns (uint256) {
        /**
         * We use integral calculus to find the approximation
         */
        int128 totalSoldFP = ABDKMath64x64.fromUInt(totalSold);
        int128 tokensToBuyFP = ABDKMath64x64.fromUInt(tokensToBuy);

        // Representing $0.60 in microdollars: 60,000,000
        int128 sixtyMillionMicrodollarsFP = ABDKMath64x64.fromUInt(60_000_000);

        // The natural logarithm of 2
        int128 ln2 = ABDKMath64x64.ln(ABDKMath64x64.fromUInt(2));

        // Constants for one million and two, in fixed-point format
        int128 oneMillion = ABDKMath64x64.fromUInt(1_000_000);
        int128 two = ABDKMath64x64.fromUInt(2);

        // Calculating the two power terms for the exponential function
        int128 powerTerm1 = ABDKMath64x64.div(totalSoldFP, oneMillion);
        int128 powerTerm2 = ABDKMath64x64.div(ABDKMath64x64.add(totalSoldFP, tokensToBuyFP), oneMillion);

        // Calculating 2 to the power of the terms
        int128 twoPowerTerm1 = ABDKMath64x64.exp(ABDKMath64x64.mul(powerTerm1, ABDKMath64x64.ln(two)));
        int128 twoPowerTerm2 = ABDKMath64x64.exp(ABDKMath64x64.mul(powerTerm2, ABDKMath64x64.ln(two)));

        // Calculating the final terms for the price
        int128 priceTerm1 = ABDKMath64x64.div(ABDKMath64x64.mul(sixtyMillionMicrodollarsFP, twoPowerTerm1), ln2);
        int128 priceTerm2 = ABDKMath64x64.div(ABDKMath64x64.mul(sixtyMillionMicrodollarsFP, twoPowerTerm2), ln2);

        // Subtracting the two terms to get the total price in fixed-point format
        int128 totalPriceFP = ABDKMath64x64.sub(priceTerm2, priceTerm1);

        // Convert the fixed-point value back to an integer, representing the price in microdollars
        return ABDKMath64x64.toUInt(totalPriceFP) * (10 ** (USDC_DECIMALS - 2));
    }

    // /// @dev helper function to get the amount of tokens that would be sold at a given price
    // function getAmountFromDesiredPrice(uint256 totalSold, uint256 desiredPrice) public view returns (uint256) {
    //     return _getAmountFromDesiredPrice(totalSold, desiredPrice, USDC_DECIMALS);
    // }

    // //TODO: decide if we want to stash this.....or just leave it here
    // function _getAmountFromDesiredPrice(uint256 totalSold, uint256 desiredPrice, uint256 decimals)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     //    return  2 * (1_000_000 * (price -.6))/(1.2) - total_sold
    //     // return  2 * (totalSold + (desiredPrice - _POINT6)) * (10**(decimals+1)) /12 - totalSold;
    //     return 2 * (desiredPrice - _POINT6) * 1_000_000 * (10 ** decimals) / _POINT6 - totalSold;
    // }

    //-----------------UTILS-----------------
    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) private pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}
