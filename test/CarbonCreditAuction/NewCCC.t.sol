// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import {TestGCC} from "../../src/testing/TestGCC.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/console.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";

contract CarbonCreditDutchAuctionTest is Test {
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    TestGCC public gcc;
    TestGLOW public glow;
    CarbonCreditDutchAuction public auction;
    address earlyLiquidityAddress = address(0x15);
    address vestingContract = address(0x16);
    uint256 constant ONE_WEEK = 1 weeks;
    uint256 constant SALE_UNIT = 1e6;

    address GCA = address(0xffaffafafa);
    address VETO_COUNCIL = address(0xfffffff);
    address GRANTS = address(0xdddaaff);

    address operator = address(0x1);
    address minerPool = address(0x2);

    function setUp() public {
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();
        vm.warp(100000);
        glow = new TestGLOW(earlyLiquidityAddress, vestingContract, GCA, VETO_COUNCIL, GRANTS);
        gcc = new TestGCC(address(this), address(this), address(glow), address(usdc), address(uniswapRouter));
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

    function test_buyOneShouldShouldEqualPointOneGlow() public {
        sendGCCToAuction(100000 ether);
        vm.warp(block.timestamp + ONE_WEEK);
        uint256 pricePerUnit = auction.getPricePerUnit();
        //1 week elapsed, price should have halved
        console.log("price per unit = ", pricePerUnit);
        //Purchase 1
        vm.startPrank(operator);
        glow.mint(operator, 10 ether);
        uint256 glowBalBefore = glow.balanceOf(operator);
        glow.approve(address(auction), 100_000_000_000_000_000 ether);
        auction.buyGCC({unitsToBuy: 1 ether / SALE_UNIT, maxPricePerUnit: pricePerUnit});
        vm.stopPrank();

        uint256 gccBalance = gcc.balanceOf(operator);
        uint256 glowBalAfter = glow.balanceOf(operator);

        console.log("gcc balance = ", gccBalance);
        uint256 glowDiff = glowBalBefore - glowBalAfter;
        console.log("glow diff = ", glowDiff);
        //Since prive halved, we should have spend .05 glow
        //We need to adjust for precision errors
        assertTrue(valFallsInRange(glowDiff, 0.0499 ether, 0.05 ether));
        assertEq(gccBalance, 1 ether);
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
