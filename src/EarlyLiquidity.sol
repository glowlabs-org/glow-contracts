// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

interface IDecimals {
    error IncorrectDecimals();

    function decimals() external view returns (uint8);
}

// add deposit functions so we can deposit to GRC and Miner Pool once those contracts are up and running

/**
 * @title EarlyLiquidity
 * @author @DavidVorick
 * @author @0xSimon
 * @notice This contract allows users to buy Glow tokens with USDC
 * @dev the cost of glow rises exponentially with the amount of glow sold
 *         -  The price at token t = 0.6 * 2^((total_sold + t)/ 1_000_000)
 * @dev to calculate the price for x tokens in real time, we use the sum of a geometric series
 */

contract EarlyLiquidity is IEarlyLiquidity {
    using ABDKMath64x64 for int128;

    /// @dev The USDC token
    IERC20 public immutable USDC_TOKEN;

    /// @dev The number of decimals for USDC
    uint256 public constant USDC_DECIMALS = 6;

    /// @dev The number 0.6 in microdollars with respect to USDC_DECIMALS
    uint256 private constant _POINT6 = 6 * (10 ** (USDC_DECIMALS - 1));

    /// @dev The total number of glow tokens to sell
    uint256 public constant TOTAL_TOKENS_TO_SELL_DIV_1E18 = 12_000_000;

    /// @dev The minimum increment that tokens can be bought in
    /// @dev this is essential so our floating point math doesn't break
    uint256 public constant MIN_TOKEN_INCREMENT = 1e18;

    //************************************************************* */
    //*****************  FLOATING POINT CONSTANTS    ************** */
    //************************************************************* */

    /// @dev Represents 1.000000693 in 64x64 format, or `r` in the geometric series
    int128 private constant _RATIO = 18_446_756_860_022_628_215;

    /// @dev Represents 0.6 USDC in 64x64 format
    int128 private constant _POINT_6 = 11068046444225730969600000;

    /// @dev Represents 1 in 64x64 format
    int128 private constant _ONE = 18446744073709551616;

    /// @dev Represents ln(r) in 64x64 format
    int128 private constant _LN_RATIO = 12786308645200;

    /// @dev Represents  1e6 in 64x64 format
    int128 private constant _ONE_MILLION = 18446744073709551616000000;

    /// @dev Represents ln(2) in 64x64 format
    int128 private constant _LN_2 = 12786308645202655659;

    /// @dev represents (1-r) in 64x64 format
    int128 private constant _DENOMINATOR = -12786313076599;

    /// @dev tokens are demagnified by 1e18 to make floating point math easier
    /// @dev the {totalSold} function returns the total sold in 1e18 (GLW DECIMALS)
    uint256 private _totalSoldDiv1e18;

    /// @dev The Glow token
    IERC20 public glowToken;

    IMinerPool public minerPool;

    //************************************************************* */
    //*******************  CONSTRUCTOR    **************** */
    //************************************************************* */

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
     * @inheritdoc IEarlyLiquidity
     */
    function buy(uint256 amount, uint256 maxCost) external {
        // Cache the minerPool in memory for gas optimization.
        IMinerPool pool = minerPool;
        address poolAddress = address(pool);

        // Check if the cached pool address is the zero address. If it is, revert the transaction.
        if (_isZeroAddress(poolAddress)) {
            _revert(IEarlyLiquidity.ZeroAddress.selector);
        }

        // Ensure the amount to buy is an increment of the MIN_TOKEN_INCREMENT.
        // If not, revert the transaction.
        if (amount % MIN_TOKEN_INCREMENT != 0) {
            _revert(IEarlyLiquidity.ModNotZero.selector);
        }
        // Divide the amount by MIN_TOKEN_INCREMENT to normalize it.
        amount = amount / MIN_TOKEN_INCREMENT;

        // Calculate the total cost of the desired amount of tokens.
        uint256 totalCost = getPrice(amount);

        // If the computed total cost is greater than the user's specified max cost, revert the transaction.
        if (totalCost > maxCost) {
            _revert(IEarlyLiquidity.PriceTooHigh.selector);
        }

        // Calculate the exact amount of tokens to send to the user. Convert the normalized amount back to its original scale.
        // Impossible to overflow since this is equal to {amount} in the function inputs
        uint256 glowToSend = amount * 1e18;

        // Check the balance of USDC in the miner pool before making a transfer.
        uint256 balBefore = USDC_TOKEN.balanceOf(poolAddress);

        // Transfer USDC from the user to the miner pool to pay for the tokens.
        SafeERC20.safeTransferFrom(USDC_TOKEN, msg.sender, poolAddress, totalCost);

        // Check the balance of USDC in the miner pool after the transfer to find the actual transferred amount.
        uint256 balAfter = USDC_TOKEN.balanceOf(poolAddress);
        //Underflow should be impossible, unless the USDC contract is hacked and malicious
        //in which case, this transaction will revert
        //For almost all cases possible, this should not underflow/revert
        uint256 diff = balAfter - balBefore;

        // Transfer the desired amount of tokens to the user.
        SafeERC20.safeTransfer(glowToken, msg.sender, glowToSend);

        // Donate the received USDC to the miner rewards pool, possibly accounting for a tax or fee.
        pool.donateToGRCMinerRewardsPoolEarlyLiquidity(address(USDC_TOKEN), diff);

        // Update the total amount of tokens sold by adding the normalized amount to the total.
        _totalSoldDiv1e18 += amount;

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
    function getPrice(uint256 amount) public view returns (uint256) {
        return _getPrice(_totalSoldDiv1e18, amount);
    }

    /**
     * @inheritdoc IEarlyLiquidity
     */
    function totalSold() public view returns (uint256) {
        return _totalSoldDiv1e18 * MIN_TOKEN_INCREMENT;
    }

    /**
     * @inheritdoc IEarlyLiquidity
     */
    function getCurrentPrice() external view returns (uint256) {
        return _getPrice(_totalSoldDiv1e18, 1);
    }

    //************************************************************* */
    //*******************     TOKEN MATH    ******************** */
    //************************************************************* */

    /**
     * @notice Calculates the price of a given amount of tokens
     * @param totalSold The total amount of tokens sold so far (divided by 1e18)
     * @param tokensToBuy The amount of tokens to buy (divided by 1e18)
     * @return The price of the tokens in microdollars
     * @dev uses the geometric series of 2 * .6^((total_sold + tokens_to_buy)/ 1_000_000)
     *             - to get the price using the sum of a geometric series
     *                - rounding errors do occur due to floating point math, but divergence is sub 1e-7
     */

    function _getPrice(uint256 totalSold, uint256 tokensToBuy) private pure returns (uint256) {
        // Check if the combined total of tokens sold and tokens to buy exceed the allowed amount.
        // If it does, revert the transaction.
        if (totalSold + tokensToBuy > TOTAL_TOKENS_TO_SELL_DIV_1E18) {
            _revert(IEarlyLiquidity.AllSold.selector);
        }

        // Convert the number of tokens to buy into a fixed-point representation.
        int128 n = ABDKMath64x64.fromUInt(tokensToBuy);

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
        // the total amount of tokens already sold.
        int128 firstTermInSeries = _getFirstTermInSeries(totalSold);

        // Compute the sum of the geometric series.
        int128 geometricSeries = (firstTermInSeries.mul(divisionResult));

        // Convert the fixed-point result back to an unsigned integer, representing the
        // final price in microdollars.
        uint256 result = geometricSeries.toUInt();

        // The following comments are for the purpose of explaining why the code cannot overflow.
        //The maximum value of totalSold is 12,000,000
        //The maximum value of tokensToBuy is 12,000,000
        // the max of n is 12,000,000
        // _LN_RATIO  = ln(1.000000693) = 0.000000693
        //The maximum value of rToTheN is e^(12,000,000 * .000000693) = 4088
        //The maximum value of numerator is 1 - 4088 = -4087
        //The maximum value of divisionResult is -4087 / 0.999999307 = 4087
        //The maximum value of firstTermInSeries is 600,000 * 2^12,000,000 / 1,000,000 = 2.5e9
        //The maximum value of geometricSeries is 2.5e9 * 4087 = 1.02e13
        //This cant overflow since 1.02e13 < 2^63-1 = 9.223372e+18


        return result;
    }

    /**
     *   @notice Calculates the first term in the geometric series for the current price of the current token
     *   @return  The first term to be used in the geometric series
     */
    function _getFirstTermInSeries(uint256 totalSold) private pure returns (int128) {
        // Convert 'totalSold' to a fixed-point representation using ABDKMath64x64.
        // This is done to perform mathematical operations with precision.
        int128 floatingPointTotalSold = ABDKMath64x64.fromUInt(totalSold);

        
        // The goal is to compute the exponent for: 2^(totalSold / 1,000,000)
        // Using logarithmic properties, this can be re-written using the identity:
        // b^c = a^(ln(b)*c) => 2^(totalSold / 1,000,000) = e^(ln(2) * totalSold / 1,000,000)
        // Here, '_LN_2' is the natural logarithm of 2, and '_ONE_MILLION' represents 1,000,000.
        int128 exponent = _LN_2.mul(floatingPointTotalSold).div(_ONE_MILLION);
        
        // Compute e^(exponent), which effectively calculates 2^(totalSold / 1,000,000)
        // because of the earlier logarithmic transformation.
        int128 baseResult = ABDKMath64x64.exp(exponent);
        
        // Multiply the result by 0.6, where '_POINT_6' is the fixed-point representation of 0.6.
        int128 result = _POINT_6.mul(baseResult);
        

        // The following comments are for the purpose of explaining why the code cannot overflow.
        //ln(2) = 0.693147......
        //floatingPointTotalSold will never be more than 12,000,000
        //so the maximum value of the exponent will be 8,316,000 / 1,000,000 = 8.316
        //None of those numbers are greater than 2^63-1 (the maximum value of an int128)
        //Max value of baseResult possible is e^8.316 = 4,088 (rounded up)
        //The max input that baseResult can take in is 43 since (e^44 > type(uint128).max > e^43)
        //We will never cause an overflow in the exponent calculation
        //Max value of result is 600,000 * 4,088 = 2,453,000,000 approx 2.5e9
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
