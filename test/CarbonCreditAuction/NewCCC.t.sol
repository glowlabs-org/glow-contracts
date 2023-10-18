// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import {TestGCC} from "../../src/testing/TestGCC.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/console.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CarbonCreditDutchAuctionTest is Test {
    TestGCC public gcc;
    TestGLOW public glow;
    CarbonCreditDutchAuction public auction;
    address earlyLiquidityAddress = address(0x15);
    address vestingContract = address(0x16);
    uint256 constant ONE_WEEK = 1 weeks;
    uint256 constant SALE_UNIT = 1e6;

    address operator = address(0x1);
    address minerPool = address(0x2);

    function setUp() public {
        vm.warp(100000);
        glow = new TestGLOW(earlyLiquidityAddress, vestingContract);
        gcc = new TestGCC(address(this), address(this),address(glow));
        //Starting price is 1:1
        auction = CarbonCreditDutchAuction(address(gcc.CARBON_CREDIT_AUCTION()));
    }

    function testReceiveGCC() public {
        sendGCCToAuction(10_000 ether);
        vm.warp(block.timestamp + ONE_WEEK / 2);
        sendGCCToAuction(20_000 ether);
        vm.warp(block.timestamp + ONE_WEEK / 2);
        // auction.logStateVariables();
    }

    function testFuzz_priceShouldHalfEveryWeekOfInactivity(uint256 weeksToWarp) public {
        vm.assume(weeksToWarp > 0 && weeksToWarp < 60);
        sendGCCToAuction(10_000 ether);
        uint256 startingPrice = auction.getPricePerUnit();
        vm.warp(block.timestamp + ONE_WEEK * weeksToWarp);
        uint256 expectedPrice = startingPrice / (2 ** weeksToWarp);
        assert(valFallsInRange(auction.getPricePerUnit(), expectedPrice * 99 / 100, expectedPrice * 101 / 100));
    }

    function test_BuyCCAuction() public {
        uint256 startingPrice = auction.getPricePerUnit();
        sendGCCToAuction(10_000 ether);
        console.log("starting price = ", startingPrice);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.startPrank(operator);
        uint256 price = auction.getPricePerUnit();
        glow.mint(operator, 100_000_000_000_000_000 ether);
        glow.approve(address(auction), 100_000_000_000_000_000 ether);
        auction.buyGCC({unitsToBuy: 10_000 ether / SALE_UNIT, maxPricePerUnit: price});
        vm.stopPrank();

        console.log("gcc balance after purchase = ", gcc.balanceOf(operator));
        // auction.logStateVariables();
        console.log("new price per unit = ", auction.getPricePerUnit());
        //add ten thousand more and warp 12 hours, and price should not change when we buy
        sendGCCToAuction(10_000 ether);
        // //12 hours
        assert(gcc.balanceOf(operator) == 10_000 ether);
        assert(auction.totalUnitsSold() == 10_000 ether / SALE_UNIT);
        console.log("[1] price per unit = ", auction.getPricePerUnit());
        vm.warp(block.timestamp + (3600 * 12));
        uint256 unitsForSale = auction.unitsForSale();
        console.log("total supply = ", auction.totalSupply());
        assert(auction.totalSupply() == 10714285714285714285714);
        assert(auction.totalSaleUnits() == auction.totalSupply() / SALE_UNIT);

        console.log("units for sale = ", unitsForSale);
        vm.startPrank(operator);
        price = auction.getPricePerUnit();
        auction.buyGCC({unitsToBuy: unitsForSale, maxPricePerUnit: price});
        vm.stopPrank();

        console.log("[2] gcc balance after purchase = ", gcc.balanceOf(operator));
        // auction.logStateVariables();
        console.log("[2] new price per unit = ", auction.getPricePerUnit());
        //warp one week
        vm.warp(block.timestamp + ONE_WEEK);
        console.log("[3] new price per unit = ", auction.getPricePerUnit());
        vm.warp(block.timestamp + ONE_WEEK);
        console.log("[4] new price per unit = ", auction.getPricePerUnit());
        vm.warp(block.timestamp + ONE_WEEK);
    }

    function test_receiveGCC_callerNotGCC_shouldRvert() public {
        vm.startPrank(address(0xdead));
        gcc.mint(address(auction), 1 ether);
        vm.expectRevert(CarbonCreditDutchAuction.CallerNotGCC.selector);
        auction.receiveGCC(1 ether);
        vm.stopPrank();
    }

    function test_buyGCC_buyingZeroUnits_shouldFail() public {
        uint256 startingPrice = auction.getPricePerUnit();
        sendGCCToAuction(10_000 ether);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.startPrank(operator);
        uint256 price = auction.getPricePerUnit();
        glow.mint(operator, 100_000_000_000_000_000 ether);
        glow.approve(address(auction), 100_000_000_000_000_000 ether);
        vm.expectRevert(CarbonCreditDutchAuction.CannotBuyZeroUnits.selector);
        auction.buyGCC({unitsToBuy: 0, maxPricePerUnit: price});
        vm.stopPrank();
    }

    function test_buyGCC_userPriceTooLow_shouldRevert() public {
        uint256 startingPrice = auction.getPricePerUnit();
        sendGCCToAuction(10_000 ether);
        console.log("starting price = ", startingPrice);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.startPrank(operator);
        uint256 price = auction.getPricePerUnit();
        glow.mint(operator, 100_000_000_000_000_000 ether);
        glow.approve(address(auction), 100_000_000_000_000_000 ether);
        vm.expectRevert(CarbonCreditDutchAuction.UserPriceNotHighEnough.selector);
        auction.buyGCC({unitsToBuy: 10_000 ether / SALE_UNIT, maxPricePerUnit: price - 1});
        vm.stopPrank();
    }

    function test_buyGCC_overpurchasingGCC_shouldRevert() public {
        uint256 startingPrice = auction.getPricePerUnit();
        sendGCCToAuction(10_000 ether);
        console.log("starting price = ", startingPrice);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.startPrank(operator);
        uint256 price = auction.getPricePerUnit();
        glow.mint(operator, 100_000_000_000_000_000 ether);
        glow.approve(address(auction), 100_000_000_000_000_000 ether);
        vm.expectRevert(CarbonCreditDutchAuction.NotEnoughGCCForSale.selector);
        auction.buyGCC({unitsToBuy: (10_000 ether / SALE_UNIT) + 1, maxPricePerUnit: price});
        vm.stopPrank();
    }

    function valFallsInRange(uint256 val, uint256 min, uint256 max) internal pure returns (bool) {
        return val >= min && val <= max;
    }

    function sendGCCToAuction(uint256 amountToSend) internal {
        vm.startPrank(address(gcc));
        gcc.mint(address(auction), amountToSend);
        auction.receiveGCC(amountToSend);
        vm.stopPrank();
    }
}
