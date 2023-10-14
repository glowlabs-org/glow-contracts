// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HalfLifeCarbonCreditAuction} from "@/libraries/HalfLifeCarbonCreditAuction.sol";
import "forge-std/console.sol";
/*
 1.    It's a dutch auction. GCC is set to a starting price (1 GLW per GCC) and then the price falls continuously over time (could be a step function to prevent friction). The rate is that the price cuts in half every week.
 2.   GCC are added to the pile of for-sale items continuously throughout each week, they are added linearly over the week on a per-second basis
3.    When someone buys GCC, the price jumps by (2 * (GCC_purchase / GCC_available)). So if someone buys all the GCC, the price doubles. If someone buys 10% of the GCC, the price goes up by 10%
4.    The price cannot go up faster than doubling every day.
 5.   Someone can buy as many GCC as they want at the current price. The price does not change until after the sale is completed.
*/

/**
 * @title CarbonCreditDutchAuction
 * @notice This contract is a reverse dutch auction for GCC.
 *         - The price has a half life of 1 week
 *         - The max that the price can grow is 2x per 24 hours
 *         - For every sale made, the price increases by the % of the total sold that the sale was
 *             - For example, if 10% of the available GCC is sold, then the price increases by 10%
 *             - If 100% of the available GCC is sold, then the price doubles
 *         - GCC is added to the pool of available GCC linearly over the course of a week
 *         - When new GCC is added, all pending vesting amounts and the new amount are vested over the course of a week
 *         - There is no cap on the amount of GCC that can be purchased in a single transaction
 *         - All GCC donations must be registered by the miner pool contract
 * @author DavidVorick
 * @author 0xSimon , 0xSimbo
 */
contract CarbonCreditDutchAuction {
    error CallerNotMinerPool();
    error UserPriceNotHighEnough();
    error NotEnoughGCCForSale();
    error CannotBuyZeroUnits();

    /// @notice The GLOW token
    IERC20 public immutable GLOW;
    /// @notice The GCC token
    IERC20 public immutable GCC;
    /// @notice The miner pool contract
    address public immutable MINER_POOL;

    /// @dev The precision (magnifier) used for calculations
    uint256 private constant PRECISION = 1e8;
    /// @dev The number of seconds in a day
    uint256 private constant ONE_DAY = uint256(1 days);
    /// @dev The number of seconds in a week
    uint256 private constant ONE_WEEK = uint256(7 days);

    /**
     * @dev a variable to keep track of the total amount of GCC that has been fully vested
     *         - it's not accurate and should only be used in conjunction with
     *             - {totalAmountReceived} to calculate the total supply
     *             - as shown in {totalSupply}
     */
    uint256 internal totalAmountFullyAvailableForSale;

    /// @notice The total amount of GLOW received from the miner pool
    uint256 public totalAmountReceived;
    uint256 public totalUnitsSold;

    /// @notice The price of GCC 24 hours ago
    uint256 public price24HoursAgo;

    /// @dev The price of GCC per sale unit
    /// @dev this price is not the actual price, and should be used in conjunction with {getPricePerUnit}
    uint256 internal pricePerSaleUnit;

    /**
     * @notice the amount of GCC sold within a single unit (0.000000000001 GCC)
     * @dev This is equal to 1*10^-12 GCC (or .000000000001 GCC)
     */
    uint256 public constant SALE_UNIT = 1e6;

    /**
     * @dev A struct to keep track of the timestamps all in a single slot
     * @param lastSaleTimestamp the timestamp of the last sale
     * @param lastReceivedTimestamp the timestamp of the last time GCC was received from the miner pool
     * @param lastPriceChangeTimestamp the timestamp of the last time the price changed
     */
    struct Timestamps {
        uint64 lastSaleTimestamp;
        uint64 lastReceivedTimestamp;
        uint64 lastPriceChangeTimestamp;
    }

    /// @notice The timestamps
    Timestamps public timestamps;

    /**
     * @param glow the GLOW token
     * @param gcc the GCC token
     * @param minerPool the miner pool contract
     * @param startingPrice the starting price of 1 unit of GCC
     */
    constructor(IERC20 glow, IERC20 gcc, address minerPool, uint256 startingPrice) {
        GLOW = glow;
        GCC = gcc;
        MINER_POOL = minerPool;
        pricePerSaleUnit = startingPrice;
        price24HoursAgo = startingPrice;
    }

    //************************************************************* */
    //************  EXTERNAL STATE CHANGING FUNCTIONS    ********* */
    //************************************************************* */

    /**
     * @notice receives GCC from the miner pool
     * @param amount the amount of GCC to receive
     * @dev this function can only be called by the miner pool contract
     */
    function receiveGCC(uint256 amount) external {
        if (msg.sender != MINER_POOL) {
            revert CallerNotMinerPool();
        }

        totalAmountFullyAvailableForSale = totalSupply();
        timestamps.lastReceivedTimestamp = uint64(block.timestamp);
        totalAmountReceived += amount;
    }

    /**
     * @notice purchases {unitsToBuy} units of GCC at a maximum price of {maxPricePerUnit} GLOW per unit
     * @param unitsToBuy the number of units to buy
     * @param maxPricePerUnit the maximum price per unit that the user is willing to pay
     */
    function buyGCC(uint256 unitsToBuy, uint256 maxPricePerUnit) external {
        if (unitsToBuy == 0) {
            revert CannotBuyZeroUnits();
        }
        Timestamps memory _timestamps = timestamps;
        uint256 _lastPriceChangeTimestamp = _timestamps.lastPriceChangeTimestamp;
        uint256 _price24HoursAgo = price24HoursAgo;
        uint256 price = getPricePerUnit();
        if (price > maxPricePerUnit) {
            revert UserPriceNotHighEnough();
        }
        uint256 gccPurchasing = unitsToBuy * SALE_UNIT;
        uint256 glowToTransfer = unitsToBuy * price;

        uint256 totalSaleUnitsAvailable = totalSaleUnits();
        uint256 saleUnitsLeftForSale = totalSaleUnitsAvailable - totalUnitsSold;

        if (saleUnitsLeftForSale < unitsToBuy) {
            revert NotEnoughGCCForSale();
        }

        uint256 newPrice = price + (price * (unitsToBuy * PRECISION / saleUnitsLeftForSale) / PRECISION);

        //If it's been more than a day since the last sale, then we can reset the price
        if (block.timestamp - _lastPriceChangeTimestamp > ONE_DAY) {
            _price24HoursAgo = price;
            price24HoursAgo = _price24HoursAgo;
            _lastPriceChangeTimestamp = block.timestamp;
        } else {
            if (newPrice * PRECISION / _price24HoursAgo > 2 * PRECISION) {
                newPrice = _price24HoursAgo * 2;
            }
        }
        pricePerSaleUnit = newPrice;

        totalUnitsSold += unitsToBuy;
        timestamps = Timestamps({
            lastSaleTimestamp: uint64(block.timestamp),
            lastReceivedTimestamp: _timestamps.lastReceivedTimestamp,
            lastPriceChangeTimestamp: uint64(_lastPriceChangeTimestamp)
        });
        GLOW.transferFrom(msg.sender, address(this), glowToTransfer);
        GCC.transfer(msg.sender, gccPurchasing);
    }

    //************************************************************* */
    //*****************  EXTERNAL GETTER FUNCTIONS    ************** */
    //************************************************************* */
    /**
     * @notice returns the price per unit of GCC
     */
    function getPricePerUnit() public view returns (uint256) {
        uint256 _lastSaleTimestamp = timestamps.lastSaleTimestamp;
        uint256 _pricePerSaleUnit = pricePerSaleUnit;
        return
            HalfLifeCarbonCreditAuction.calculateHalfLifeValue(_pricePerSaleUnit, block.timestamp - _lastSaleTimestamp);
    }

    /**
     * @notice returns the total supply of GCC available for sale in WEI
     * @dev this is not to be confused with the total units of GCC available for sale
     */
    function totalSupply() public view returns (uint256) {
        Timestamps memory _timestamps = timestamps;
        uint256 _lastReceivedTimestamp = _timestamps.lastReceivedTimestamp;
        uint256 _totalAmountReceived = totalAmountReceived;
        uint256 _totalUnitsSold = totalUnitsSold;
        uint256 amountThatNeedsToVest = _totalAmountReceived - totalAmountFullyAvailableForSale;
        uint256 timeDiff = min(ONE_WEEK, block.timestamp - _lastReceivedTimestamp);
        return (totalAmountFullyAvailableForSale + amountThatNeedsToVest * timeDiff / ONE_WEEK);
    }

    /**
     * @notice returns the number of units of GCC available for sale
     */
    function unitsForSale() external view returns (uint256) {
        return totalSaleUnits() - totalUnitsSold;
    }

    /**
     * @notice returns the cumulative total number of units of GCC that have been sold or are available for sale
     */
    function totalSaleUnits() public view returns (uint256) {
        return totalSupply() / (SALE_UNIT);
    }

    //************************************************************* */
    //*****************  INTERNAL GETTER FUNCTIONS   ************** */
    //************************************************************* */
    /**
     * @param a the first number
     * @param b the second number
     * @return smaller - the smaller of the two numbers
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

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
