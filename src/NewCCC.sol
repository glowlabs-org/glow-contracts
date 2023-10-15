// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HalfLifeCarbonCreditAuction} from "@/libraries/HalfLifeCarbonCreditAuction.sol";
import "forge-std/console.sol";

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
    error CallerNotGCC();
    error UserPriceNotHighEnough();
    error NotEnoughGCCForSale();
    error CannotBuyZeroUnits();

    /// @notice The GLOW token
    IERC20 public immutable GLOW;
    /// @notice The GCC token
    IERC20 public immutable GCC;

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
        uint64 firstReceivedTimestamp;
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
        if (msg.sender != address(GCC)) {
            _revert(CallerNotGCC.selector);
        }
        Timestamps memory _timestamps = timestamps;
        totalAmountFullyAvailableForSale = totalSupply();
        // timestamps.lastReceivedTimestamp = uint64(block.timestamp);
        timestamps = Timestamps({
            lastSaleTimestamp: _timestamps.lastSaleTimestamp,
            lastReceivedTimestamp: uint64(block.timestamp),
            lastPriceChangeTimestamp: _timestamps.lastPriceChangeTimestamp,
            firstReceivedTimestamp: _timestamps.firstReceivedTimestamp == 0
                ? uint64(block.timestamp)
                : _timestamps.firstReceivedTimestamp
        });
        totalAmountReceived += amount;
    }

    /**
     * @notice purchases {unitsToBuy} units of GCC at a maximum price of {maxPricePerUnit} GLOW per unit
     * @param unitsToBuy the number of units to buy
     * @param maxPricePerUnit the maximum price per unit that the user is willing to pay
     */
    function buyGCC(uint256 unitsToBuy, uint256 maxPricePerUnit) external {
        if (unitsToBuy == 0) {
            _revert(CannotBuyZeroUnits.selector);
        }
        Timestamps memory _timestamps = timestamps;
        uint256 _lastPriceChangeTimestamp = _timestamps.lastPriceChangeTimestamp;
        uint256 _price24HoursAgo = price24HoursAgo;
        uint256 price = getPricePerUnit();
        if (price > maxPricePerUnit) {
            _revert(UserPriceNotHighEnough.selector);
        }
        uint256 gccPurchasing = unitsToBuy * SALE_UNIT;
        uint256 glowToTransfer = unitsToBuy * price;

        uint256 totalSaleUnitsAvailable = totalSaleUnits();
        uint256 saleUnitsLeftForSale = totalSaleUnitsAvailable - totalUnitsSold;

        if (saleUnitsLeftForSale < unitsToBuy) {
            _revert(NotEnoughGCCForSale.selector);
        }

        uint256 newPrice = price + (price * (unitsToBuy * PRECISION / saleUnitsLeftForSale) / PRECISION);

        //The new price can never grow more than 100% in 24 hours
        if (newPrice * PRECISION / _price24HoursAgo > 2 * PRECISION) {
            newPrice = _price24HoursAgo * 2;
        }
        //If it's been more than a day since the last sale, then update the price
        //To the price in the current tx
        //Also update the last price change timestamp
        if (block.timestamp - _lastPriceChangeTimestamp > ONE_DAY) {
            price24HoursAgo = price;
            _lastPriceChangeTimestamp = block.timestamp;
        }

        //
        pricePerSaleUnit = newPrice;

        totalUnitsSold += unitsToBuy;
        timestamps = Timestamps({
            lastSaleTimestamp: uint64(block.timestamp),
            lastReceivedTimestamp: _timestamps.lastReceivedTimestamp,
            lastPriceChangeTimestamp: uint64(_lastPriceChangeTimestamp),
            firstReceivedTimestamp: _timestamps.firstReceivedTimestamp
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
        Timestamps memory _timestamps = timestamps;
        uint256 _lastSaleTimestamp = _timestamps.lastSaleTimestamp;
        uint256 firstReceivedTimestamp = _timestamps.firstReceivedTimestamp;
        if (firstReceivedTimestamp == 0) {
            return pricePerSaleUnit;
        }
        if (_lastSaleTimestamp == 0) {
            _lastSaleTimestamp = firstReceivedTimestamp;
        }
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
