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

contract CarbonCreditDutchAuction {
    error CallerNotMinerPool();
    error UserPriceNotHighEnough();
    error NotEnoughGCCForSale();
    error CannotBuyZeroUnits();

    IERC20 public immutable GLOW;
    IERC20 public immutable GCC;

    uint256 private constant PRECISION = 1e8;
    uint256 private constant ONE_DAY = uint256(1 days);
    uint256 private constant ONE_WEEK = uint256(7 days);
    address public immutable MINER_POOL;

    //Vesting
    uint256 public vestingSlope;
    uint256 public lastReceivedTimestamp;
    uint256 public totalAmountReceived;
    uint256 public totalAmountFullyAvailableForSale;
    uint256 public totalUnitsSold;

    //Price
    uint256 public price24HoursAgo;
    uint256 public pricePerSaleUnit;
    uint256 public lastSaleTimestamp;

    //The lowest price that GCC can be sold for
    //is 1e12 GLOW per 1 GCC wei

    //Users buy GCC in units of 1e6
    //This is equal to 1*10^-12 GCC
    uint256 public constant SALE_UNIT = 1e6;
    uint256 public constant SALE_UNIT_COMPLEMENT = 1e18 - SALE_UNIT;

    struct Timestamps {
        uint64 lastSaleTimestamp;
        uint64 lastReceivedTimestamp;
    }

    Timestamps public timestamps;
    /**
     * Every time GCC is added, the amount added needs to vest over the course of a week.
     *     We can have a mapping,
     *     addNonce -> amountAdded,startingTimestamp
     *     however, the amount added gonna be a PITA
     */

    constructor(IERC20 glow, IERC20 gcc, address minerPool, uint256 startingPrice) {
        GLOW = glow;
        GCC = gcc;
        MINER_POOL = minerPool;
        pricePerSaleUnit = startingPrice;
        price24HoursAgo = startingPrice;
    }

    function receiveGCC(uint256 amount) external {
        if (msg.sender != MINER_POOL) {
            revert CallerNotMinerPool();
        }

        totalAmountFullyAvailableForSale = totalSupply();
        timestamps.lastReceivedTimestamp = uint64(block.timestamp);
        totalAmountReceived += amount;
    }

    function logStateVariables() public {
        Timestamps memory _timestamps = timestamps;
        uint256 _lastReceivedTimestamp = _timestamps.lastReceivedTimestamp;
        uint256 _lastSaleTimestamp = _timestamps.lastSaleTimestamp;
        console.log("lastReceivedTimestamp: %s", (_lastReceivedTimestamp));
        console.log("lastSaleTimestamp: %s", (_lastSaleTimestamp));
        console.log("totalAmountReceived: %s", (totalAmountReceived));
        console.log("totalAmountFullyAvailableForSale: %s", (totalAmountFullyAvailableForSale));
        console.log("totalUnitsSold: %s", (totalUnitsSold));
        console.log("price24HoursAgo: %s", (price24HoursAgo));
        console.log("pricePerSaleUnit: %s", (pricePerSaleUnit));
        console.log("total amount available for sale: %s", (totalSupply()));
        console.log("total sale units: %s", (totalSaleUnits()));
    }

    function buyGCC(uint256 unitsToBuy, uint256 maxPricePerUnit) external {
        if (unitsToBuy == 0) {
            revert CannotBuyZeroUnits();
        }
        uint256 _lastSaleTimestamp = timestamps.lastSaleTimestamp;
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
        if (block.timestamp - _lastSaleTimestamp > ONE_DAY) {
            _price24HoursAgo = price;
            price24HoursAgo = _price24HoursAgo;
            timestamps.lastSaleTimestamp = uint64(block.timestamp);
        } else {
            if (newPrice * PRECISION / _price24HoursAgo > 2 * PRECISION) {
                newPrice = _price24HoursAgo * 2;
            }
        }
        pricePerSaleUnit = newPrice;

        totalUnitsSold += unitsToBuy;
        GLOW.transferFrom(msg.sender, address(this), glowToTransfer);

        GCC.transfer(msg.sender, gccPurchasing);
    }

    function getPricePerUnit() public view returns (uint256) {
        uint256 _lastSaleTimestamp = lastSaleTimestamp;
        uint256 _pricePerSaleUnit = pricePerSaleUnit;
        return HalfLifeCarbonCreditAuction.calculateHalfLifeValue(_pricePerSaleUnit, _lastSaleTimestamp);
    }

    function totalSupply() public view returns (uint256) {
        Timestamps memory _timestamps = timestamps;
        uint256 _lastReceivedTimestamp = _timestamps.lastReceivedTimestamp;
        uint256 _totalAmountReceived = totalAmountReceived;
        uint256 _totalUnitsSold = totalUnitsSold;
        uint256 amountThatNeedsToVest = _totalAmountReceived - totalAmountFullyAvailableForSale;
        uint256 timeDiff = min(ONE_WEEK, block.timestamp - _lastReceivedTimestamp);
        return (totalAmountFullyAvailableForSale + amountThatNeedsToVest * timeDiff / ONE_WEEK);
    }

    function unitsForSale() public view returns (uint256) {
        return totalSaleUnits() - totalUnitsSold;
    }

    function totalSaleUnits() public view returns (uint256) {
        return totalSupply() / (SALE_UNIT);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _revert(bytes4 selector) internal pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}
