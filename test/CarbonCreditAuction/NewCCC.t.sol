// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import {TestGCC} from "../../src/testing/TestGCC.sol";
import {CarbonCreditDutchAuction} from "@/NewCCC.sol";
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
        gcc = new TestGCC(address(this), address(this), address(this));
        glow = new TestGLOW(earlyLiquidityAddress, vestingContract);
        //Starting price is 1:1
        auction = new CarbonCreditDutchAuction(glow, gcc, minerPool, SALE_UNIT);
    }

    function testReceiveGCC() public {
        sendGCCToAuction(10_000 ether);
        vm.warp(block.timestamp + ONE_WEEK / 2);
        sendGCCToAuction(20_000 ether);
        vm.warp(block.timestamp + ONE_WEEK / 2);
        auction.logStateVariables();
    }

    function test_BuyCCAuction() public {
        sendGCCToAuction(10_000 ether);
        vm.warp(block.timestamp + ONE_WEEK);
        vm.startPrank(operator);
        uint256 price = auction.getPricePerUnit();
        glow.mint(operator, 100_000_000_000_000_000 ether);
        glow.approve(address(auction), 100_000_000_000_000_000 ether);
        auction.buyGCC({unitsToBuy: 10_000 ether / SALE_UNIT, maxPricePerUnit: price});
        vm.stopPrank();

        // console.log("gcc balance after purchase = ", gcc.balanceOf(operator));
        // // auction.logStateVariables();
        // console.log("new price per unit = " , auction.getPricePerUnit());
        // //add ten thousand more and warp 12 hours, and price should not change when we buy
        sendGCCToAuction(10_000 ether);
        // //12 hours
        assert(gcc.balanceOf(operator) == 10_000 ether);
        assert(auction.totalUnitsSold() == 10_000 ether / SALE_UNIT);
        vm.warp(block.timestamp + (3600 * 12));
        uint256 unitsForSale = auction.unitsForSale();
        console.log("total supply = ", auction.totalSupply());
        console.log("units for sale = ", unitsForSale);
        vm.startPrank(operator);
        price = auction.getPricePerUnit();
        auction.buyGCC({unitsToBuy: unitsForSale, maxPricePerUnit: price});
        vm.stopPrank();

        console.log("[2] gcc balance after purchase = ", gcc.balanceOf(operator));
        // auction.logStateVariables();
        console.log("[2] new price per unit = ", auction.getPricePerUnit());
    }

    function sendGCCToAuction(uint256 amountToSend) internal {
        vm.startPrank(minerPool);
        gcc.mint(address(auction), amountToSend);
        auction.receiveGCC(amountToSend);
        vm.stopPrank();
    }
}
