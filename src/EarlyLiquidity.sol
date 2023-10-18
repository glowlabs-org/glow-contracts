// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

interface IDecimals {
    error IncorrectDecimals();

    function decimals() external view returns (uint8);
}

/**
 * @title EarlyLiquidity
 * @author @DavidVorick
 * @author twitter: @0xSimon github: @0xSimbo
 * @notice This contract allows users to buy Glow tokens with USDC
 * @dev the cost of glow rises exponentially with the amount of glow sold
 *         -  The price at increment x = 0.006 * 2^((x)/ 100_000_000)
 *            - if the function above to get price of increment x if f(x)
 *            - Then, the price to buy y tokens is Σ f(x) from x = the total increments sold, to x = the total increments sold + y
 *            - For example, to buy the first ten increments, (aka the first .1 tokens), the price is
 *                 -   f(0) + f(1) .... + f(9)
 *                 - To buy the next ten increments, or token .1 -> .2, the price is
 *                 -   f(10) + f(11) ... + f(19)
 * @dev to calculate the price for y tokens in real time, we use the sum of a geometric series which allows us
 *         - to efficiently calculate the price of y tokens in real time rather than looping through all the increments
 */

contract EarlyLiquidity is IEarlyLiquidity {
    using ABDKMath64x64 for int128;

    /// @dev The number 0.006 in microdollars with respect to USDC_DECIMALS
    uint256 private constant _POINT_ZERO_ZERO6 = 6 * (10 ** (USDC_DECIMALS - 3));

    /// @dev Represents 1.0000000069314718 in 64x64 format, or `r` in the geometric series
    int128 private constant _RATIO = 18446744201572638720;

    /// @dev Represents 0.006 USDC in 64x64 format
    int128 private constant _POINT_ZERO_ZERO_6 = 110680464442257309696000;

    /// @dev Represents 1 in 64x64 format
    int128 private constant _ONE = 18446744073709551616;

    /// @dev Represents ln(r) in 64x64 format
    int128 private constant _LN_RATIO = 127863086660;

    /// @dev Represents  1e8 in 64x64 format
    int128 private constant _ONE_HUNDRED_MILLION = 100_000_000 << 64;

    /// @dev Represents ln(2) in 64x64 format
    int128 private constant _LN_2 = 12786308645202655659;

    /// @dev represents (1-r) in 64x64 format
    /// @dev r =  1 - 1.0000000069314718 =  0000000069314718
    int128 private constant _DENOMINATOR = -127863086349;

    /// @dev tokens are demagnified by 1e18 to make floating point math easier
    /// @dev the {totalSold} function returns the total sold in 1e18 (GLW DECIMALS)
    uint256 private _totalIncrements;

    /**
     * @notice USDC token
     * @dev The USDC token
     */
    IERC20 public immutable USDC_TOKEN;

    /// @dev The number of decimals for USDC
    uint256 public constant USDC_DECIMALS = 6;

    /**
     * @notice The address of the holding contract
     * @dev the holding contract holds all GRC tokens
     */
    address public immutable HOLDING_CONTRACT;

    /**
     * @notice the minimum increment that tokens can be bought in
     *     -   .01 GLW
     * @dev The minimum increment that tokens can be bought in
     * @dev this is essential so our floating point math doesn't break
     * @dev .01 GLW
     */
    uint256 public constant MIN_TOKEN_INCREMENT = 1e16;

    /**
     * @notice the total amount of .01 increments to sell
     *     - equals to 12,000,000 GLW total
     * @dev The total number of glow tokens to sell
     * @dev 12 million GLOW tokens
     * @dev .01 * 1_200_000_000 = 12_000_000
     */
    uint256 public constant TOTAL_INCREMENTS_TO_SELL = 1_200_000_000;

    //************************************************************* */
    //*****************  FLOATING POINT CONSTANTS    ************** */
    //************************************************************* */

    /// @notice The Glow token
    IERC20 public glowToken;

    /// @notice The miner pool contract
    /// @dev all USDC is donated to the miner pool
    IMinerPool public minerPool;

    //************************************************************* */
    //*******************  CONSTRUCTOR    **************** */
    //************************************************************* */

    /**
     * @notice Constructs the EarlyLiquidity contract
     * @param _usdcAddress The address of the USDC token
     * @param _holdingContract The address of the holding contract
     * @dev does not take in Glow token since it is not deployed yet
     */
    constructor(address _usdcAddress, address _holdingContract) payable {
        USDC_TOKEN = IERC20(_usdcAddress);
        uint256 decimals = uint256(IDecimals(_usdcAddress).decimals());
        if (decimals != USDC_DECIMALS) {
            _revert(IDecimals.IncorrectDecimals.selector);
        }
        HOLDING_CONTRACT = _holdingContract;
    }

    /**
     * @inheritdoc IEarlyLiquidity
     */
    function buy(uint256 increments, uint256 maxCost) external {
        // Cache the minerPool in memory for gas optimization.
        IMinerPool pool = minerPool;
        address _holdingContract = HOLDING_CONTRACT;

        // // Check if the cached pool address is the zero address. If it is, revert the transaction.
        // if (_isZeroAddress(poolAddress)) {
        //     _revert(IEarlyLiquidity.ZeroAddress.selector);
        // }

        // Calculate the total cost of the desired amount of tokens.
        uint256 totalCost = getPrice(increments);

        // If the computed total cost is greater than the user's specified max cost, revert the transaction.
        if (totalCost > maxCost) {
            _revert(IEarlyLiquidity.PriceTooHigh.selector);
        }

        // Calculate the exact amount of tokens to send to the user. Convert the normalized increments back to its original scale.
        // Impossible to overflow since this is equal to {increments} in the function inputs
        // 1 increment = .01 (or 1e16) glw
        uint256 glowToSend = increments * 1e16;

        // Check the balance of USDC in the miner pool before making a transfer.
        uint256 balBefore = USDC_TOKEN.balanceOf(_holdingContract);

        // Transfer USDC from the user to the miner pool to pay for the tokens.
        SafeERC20.safeTransferFrom(USDC_TOKEN, msg.sender, _holdingContract, totalCost);

        // Check the balance of USDC in the miner pool after the transfer to find the actual transferred amount.
        uint256 balAfter = USDC_TOKEN.balanceOf(_holdingContract);
        //Underflow should be impossible, unless the USDC contract is hacked and malicious
        //in which case, this transaction will revert
        //For almost all cases possible, this should not underflow/revert
        uint256 diff = balAfter - balBefore;

        // Transfer the desired amount of tokens to the user.
        SafeERC20.safeTransfer(glowToken, msg.sender, glowToSend);

        // Donate the received USDC to the miner rewards pool, possibly accounting for a tax or fee.
        pool.donateToGRCMinerRewardsPoolEarlyLiquidity(address(USDC_TOKEN), diff);

        // Update the total amount of tokens sold by adding the normalized amount to the total.
        _totalIncrements += increments;

        // Emit an event to log the purchase details.
        emit IEarlyLiquidity.Purchase(msg.sender, glowToSend, totalCost);

        // End of function; the explicit 'return' here is unnecessary but it indicates the function's conclusion.
        return;
    }

    //************************************************************* */
    //*******************  ONE TIME USE SETTERS    **************** */
    //************************************************************* */

    /**
     * @notice Sets the glow token address
     * @param _glowToken The address of the glow token
     * @dev Can only be called once
     */
    function setGlowToken(address _glowToken) external {
        require(address(glowToken) == address(0), "Glow token already set");
        glowToken = IERC20(_glowToken);
    }

    /**
     * @notice - one time use function to set the miner pool address
     * @param _minerPoolAddress - the address of the miner pool contract
     * @dev should only be able to be set once
     */
    function setMinerPool(address _minerPoolAddress) external {
        if (_isZeroAddress(_minerPoolAddress)) _revert(IEarlyLiquidity.ZeroAddress.selector);
        if (!_isZeroAddress(address(minerPool))) _revert(IEarlyLiquidity.MinerPoolAlreadySet.selector);
        minerPool = IMinerPool(_minerPoolAddress);
    }

    //************************************************************* */
    //*******************     GETTERS    ******************** */
    //************************************************************* */

    /**
     * @inheritdoc IEarlyLiquidity
     */
    function getPrice(uint256 incrementsToPurchase) public view returns (uint256) {
        if (incrementsToPurchase == 0) return 0;

        return _getPrice(_totalIncrements, incrementsToPurchase);
    }

    /**
     * @inheritdoc IEarlyLiquidity
     */
    function totalSold() public view returns (uint256) {
        return _totalIncrements * MIN_TOKEN_INCREMENT;
    }

    /**
     * @inheritdoc IEarlyLiquidity
     */
    function getCurrentPrice() external view returns (uint256) {
        return _getPrice(_totalIncrements, 1);
    }

    //************************************************************* */
    //*******************     TOKEN MATH    ******************** */
    //************************************************************* */

    /**
     * @notice Calculates the price of a given amount of tokens
     * @param totalIncrementsSold The total amount of .01 increments sold
     * @param incrementsToBuy The amount of .01 increments to buy
     * @return price price of the increments to purchase in USDC
     * @dev since our increments are in .01, the function evaluates to Σ .006 * 2^((incrementId)/ 100_000_000)
     *         - for increment id = totalIncrementsSold  id: to incrementId = incrementsToBuy
     *         - rounding errors do occur due to floating point math, but divergence is sub 1e-7
     */

    function _getPrice(uint256 totalIncrementsSold, uint256 incrementsToBuy) private pure returns (uint256) {
        // Check if the combined total of tokens sold and tokens to buy exceed the allowed amount.
        // If it does, revert the transaction.
        if (totalIncrementsSold + incrementsToBuy > TOTAL_INCREMENTS_TO_SELL) {
            _revert(IEarlyLiquidity.AllSold.selector);
        }

        // Convert the number of increments to buy into a fixed-point representation.
        int128 n = ABDKMath64x64.fromUInt(incrementsToBuy);

        // Compute r^n, where 'r' is the common ratio of the geometric series.
        // Using logarithmic properties, we compute the exponent as: n * ln(r).
        // This step computes the value of r raised to the power of n.
        int128 rToTheN = ABDKMath64x64.exp(ABDKMath64x64.mul(n, _LN_RATIO));

        // Calculate the numerator for the sum formula of an infinite geometric series:
        // numerator = 1 - r^n
        int128 numerator = _ONE.sub(rToTheN);

        // Divide the numerator by the denominator, where the denominator is typically
        // (1 - r) for the sum of an infinite geometric series. Here, the denominator
        // the fixed-point representation of (1 - r).
        int128 divisionResult = numerator.div(_DENOMINATOR);

        // Calculate the first term in the geometric series. The first term is based on
        // the total amount of increments already sold.
        int128 firstTermInSeries = _getFirstTermInSeries(totalIncrementsSold);

        //divisionResult > than geometricSeries, so we convert divisionResult to uint256
        uint256 firstTimeInSerieWithFixed = uint256(int256(firstTermInSeries));
        //divisionResult is always positive so we can cast it to uint256
        uint256 divUint = uint256(int256(divisionResult));
        //We do the fixed point math in uint256 domain since we know that the result will be positive
        //Below is a fixed point multiplication
        uint256 mulResFixed = firstTimeInSerieWithFixed * divUint >> 64;
        //convert {mulResFixed} back to uint256
        return mulResFixed >> 64;

        // The following comments are for the purpose of explaining why the code cannot overflow.
        //The maximum value of totalIncrementsSold is 1,200,000,000
        //The maximum value of incrementsToBuy is     1,200,000,000
        //The max value of n is 1,200,000
        // _LN_RATIO  = ln(1.0000000069314718)
        //The maximum value of rToTheN is e^(1,200,000,000 * ln(r)) = e^8.317766180304424 = 4096.000055644491
        //The maximum value of numerator is 1 -  4096 = -4095
        //The maximum value of divisionResult is -4095 / -0.0000000069314718  = 590,783,619,721.2834
        //The maximum value of firstTermInSeries is 6000 * 2^12 = 24576000
        //The maximum value of geometricSeries is 24576000 * 590,783,619,721.2834  = 14,499,840,000,783,619,721
        //This cant overflow since it's < 2^63-1
    }

    /**
     *   @notice Calculates the first term in the geometric series for the current price of the current token
     *  @param totalIncrementsSold - the total number of increments that have already been sold
     *   @return  firstTerm -  first term to be used in the geometric series
     */

    function _getFirstTermInSeries(uint256 totalIncrementsSold) private pure returns (int128) {
        // Convert 'totalSold' to a fixed-point representation using ABDKMath64x64.
        // This is done to perform mathematical operations with precision.
        int128 floatingPointTotalSold = ABDKMath64x64.fromUInt(totalIncrementsSold);

        // The goal is to compute the exponent for: 2^(totalIncrements / 100,000,000)
        // Using logarithmic properties, this can be re-written using the identity:
        // b^c = a^(ln(b)*c) => 2^(totalIncrements / 100,000,000) = e^(ln(2) * totalIncrements / 100,000,000)
        // Here, '_LN_2' is the natural logarithm of 2, and '_ONE_HUNDRED_MILLION' represents 100,000,000.
        int128 exponent = _LN_2.mul(floatingPointTotalSold).div(_ONE_HUNDRED_MILLION);

        // Compute e^(exponent), which effectively calculates 2^(totalIncrements / 100,000,000)
        // because of the earlier logarithmic transformation.
        int128 baseResult = ABDKMath64x64.exp(exponent);

        // Multiply the result by 0.006, where '_POINT_ZERO_ZERO_6' is the fixed-point representation of 0.006.
        int128 result = _POINT_ZERO_ZERO_6.mul(baseResult);

        // The following comments are for the purpose of explaining why the code cannot overflow.
        //ln(2) = 0.693147......
        //floatingPointTotalSold will never be more than 1,200,000,000
        //so the maximum value of the exponent will be .693147 * 1,200,000,000 / 100,000,000 = 8.316
        //None of those numbers are greater than 2^63-1 (the maximum value of an int128)
        //Max value of baseResult possible is e^8.316 = 4,089 (rounded up)
        //The max input that baseResult can take in is 43 since (e^44 > type(uint128).max > e^43)
        //We will never cause an overflow in the exponent calculation
        //Max value of result is 6,000 * 4,088 = 2,453,000,000 approx 2.5e9
        //This is well within the range of 2^63-1 = 9,223,372,036,854,775,807 approx 9.223372e+18
        // Return the final result.
        return result;
    }

    //************************************************************* */
    //*******************     UTILS    ******************** */
    //************************************************************* */

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

    /**
     * @dev for more efficient zero address checks
     */
    function _isZeroAddress(address a) private pure returns (bool isZero) {
        assembly {
            isZero := iszero(a)
        }
    }
}
