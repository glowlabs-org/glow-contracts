// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ABDKMath64x64} from "@/libraries/ABDKMath64x64.sol";
import "forge-std/console.sol";
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

    uint256 private constant _TOTAL_TOKENS_TO_SELL_DIV_1E18 = 12_000_000;

    /// @dev The minimum increment that tokens can be bought in
    /// @dev this is essential so our floating point math doesn't break
    uint256 public constant MIN_TOKEN_INCREMENT = 1e18;

    //--FLOATING POINT CONSTANTS (IN FIXED POINT FORMAT)--

    /// @dev Represents 1.000000693 in 64x64 format, or `r` in the geometric series
    //TODO: make sure the _RATIO = 1.0000006931474208.... add precision
    int128 private constant _RATIO = 18_446_756_860_022_628_215;


    /// @dev Represents 0.6 USDC in 64x64 format
    int128 private constant _POINT_6 = 11068046444225730969600000;

    /// @dev Represents 1 in 64x64 format
    int128 private constant _ONE = 18446744073709551616;

    /// @dev Represents ln(r) in 64x64 format
    int128 private constant _LN_RATIO = 12786308645200;

    /// @dev Represents  (1-r) in 64x64 format
    int128 private constant _DIVISOR = 18446744073709551616000000;

    /// @dev Represents ln(2) in 64x64 format
    int128 private constant _LN_2 = 12786308645202655659;

    /// @dev tokens are demagnified by 1e18 to make floating point math easier
    /// @dev the {totalSold} function returns the total sold in 1e18 (GLW DECIMALS)
    uint256 private _totalSoldDiv1e18;

    /// @dev The Glow token
    IERC20 public glowToken;

    IMinerPool public minerPool;

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
     * @inheritdoc IEarlyLiquidity
     */
    function buy(uint256 amount, uint256 maxCost) external {
        //cache in mem
        IMinerPool pool = minerPool;
        address poolAddress = address(pool);
        if (_isZeroAddress(poolAddress)) {
            _revert(IEarlyLiquidity.ZeroAddress.selector);
        }

        if (amount % MIN_TOKEN_INCREMENT != 0) {
            _revert(IEarlyLiquidity.ModNotZero.selector);
        }
        amount = amount / MIN_TOKEN_INCREMENT;
        uint256 totalCost = getPrice(amount);
        if (totalCost > maxCost) {
            _revert(IEarlyLiquidity.PriceTooHigh.selector);
        }
        uint256 glowToSend = amount * 1e18;
        uint256 balBefore = USDC_TOKEN.balanceOf(poolAddress);
        SafeERC20.safeTransferFrom(USDC_TOKEN, msg.sender, poolAddress, totalCost);
        uint256 balAfter = USDC_TOKEN.balanceOf(poolAddress);
        uint256 diff = balAfter - balBefore;
        //Take into account a possible tax.
        pool.donateToGRCMinerRewardsPoolEarlyLiquidity(address(USDC_TOKEN), diff);

        SafeERC20.safeTransfer(glowToken, msg.sender, glowToSend);
        _totalSoldDiv1e18 += amount;
        emit IEarlyLiquidity.Purchase(msg.sender, glowToSend, totalCost);
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
     *                - rounding errors do occur due to floating point math, but divergence is sub 1e-7%
     */

    function _getPrice(uint256 totalSold, uint256 tokensToBuy) private pure returns (uint256) {
        if (totalSold + tokensToBuy > _TOTAL_TOKENS_TO_SELL_DIV_1E18) {
            _revert(IEarlyLiquidity.AllSold.selector);
        }
        int128 n = ABDKMath64x64.fromUInt(tokensToBuy);
        int128 rToTheN = ABDKMath64x64.exp(ABDKMath64x64.mul(n, _LN_RATIO));
        int128 numerator = _ONE.sub(rToTheN);
        int128 denominator = _ONE.sub(_RATIO);

        // Do the division first
        int128 divisionResult = numerator.div(denominator);

        int128 firstTermInSeries = _getFirstTermInSeries(totalSold);
        int128 geometricSeries = (firstTermInSeries.mul(divisionResult));

        int256 result = geometricSeries.toInt();

        require(result >= 0, "Negative value returned");
        return uint256(result);
    }

    function _getFirstTermInSeries(uint256 totalSold) private pure returns (int128) {
        int128 scaledTotalSold = ABDKMath64x64.fromUInt(totalSold);
        // Calculate the exponent: (ln(2) * totalSold) / 1,000,000
        int128 exponent = _LN_2.mul(scaledTotalSold).div(_DIVISOR);

        // Now, compute 2^(exponent)
        int128 baseResult = ABDKMath64x64.exp(exponent);

        // Finally, multiply by 0.6
        int128 result = _POINT_6.mul(baseResult);

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
