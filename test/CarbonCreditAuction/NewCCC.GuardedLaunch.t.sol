// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "../../src/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {TestGCCGuardedLaunch} from "../../src/testing/GuardedLaunch/TestGCC.GuardedLaunch.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/console.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {Holding, ClaimHoldingArgs, IHoldingContract, HoldingContract} from "@/HoldingContract.sol";

contract CarbonCreditDutchAuctionGuardedLaunchTest is Test {
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    TestGCCGuardedLaunch public gcc;
    TestGLOWGuardedLaunch public glow;
    TestUSDG usdg;
    CarbonCreditDutchAuction public auction;
    VetoCouncil public vetoCouncil;
    MockMinerPoolAndGCA public minerPoolAndGCA;
    HoldingContract holdingContract;

    address earlyLiquidityAddress = address(0x15);
    address vestingContract = address(0x16);
    uint256 constant ONE_WEEK = 1 weeks;
    uint256 constant SALE_UNIT = 1e6;

    address operator = address(0x1);
    address minerPool = address(0x2);
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);
    address governance = address(0xfffffaaaeeee);
    address SIMON = address(0xaaa115514);
    address OTHER_VETO_COUNCIL_MEMBER = address(0x23414123414099);
    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);

    address deployer = address(tx.origin);

    function setUp() public {
        vm.startPrank(deployer);
        vm.warp(100000);

        uint256 deployNonce = vm.getNonce(deployer);
        uniswapFactory = new UnifapV2Factory(); //deployNonce
        weth = new WETH9(); //deployNonce + 1
        uniswapRouter = new UnifapV2Router(address(uniswapFactory)); //deployNonce + 2
        usdc = new MockUSDC(); //deployNonce + 3

        address precomputedMinerPool = computeCreateAddress(deployer, deployNonce + 9);
        address precomputedVeto = computeCreateAddress(deployer, deployNonce + 7);
        address precomputedGCC = computeCreateAddress(deployer, deployNonce + 4);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployNonce + 8);
        address precomputedGlow = computeCreateAddress(deployer, deployNonce + 5);
        address precomputedUSDG = computeCreateAddress(deployer, deployNonce + 6);
        address precomputedImpactCatalyst = computeCreateAddress(precomputedGCC, 1); //GCC deploys impact catalyst as it's second create address

        // gcc = new TestGCC(address(this), address(this),address(glow),address(usdc),address(uniswapRouter));
        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: precomputedMinerPool,
            _governance: address(governance),
            _glowToken: precomputedGlow,
            _usdg: precomputedUSDG,
            _vetoCouncilAddress: precomputedVeto,
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployNonce + 4

        glow = new TestGLOWGuardedLaunch(
            earlyLiquidityAddress,
            vestingContract,
            precomputedMinerPool,
            precomputedVeto,
            address(0xdead), //
            SIMON,
            address(precomputedUSDG),
            address(uniswapFactory),
            address(gcc)
        ); //deployNonce + 5

        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: address(glow),
            _gcc: precomputedGCC,
            _holdingContract: precomputedHoldingContract,
            _vetoCouncilContract: precomputedVeto,
            _impactCatalyst: precomputedImpactCatalyst
        }); //deployNonce + 6
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_VETO_COUNCIL_MEMBER);

        vetoCouncil = new VetoCouncil(governance, address(glow), startingAgents); //deployNonce + 7
        holdingContract = new HoldingContract(address(vetoCouncil), precomputedMinerPool); //deployNonce + 8

        minerPoolAndGCA = new MockMinerPoolAndGCA(
            startingAgents,
            address(glow),
            governance,
            keccak256("requirementsHash"),
            earlyLiquidityAddress,
            address(usdg),
            address(vetoCouncil),
            address(address(holdingContract)),
            precomputedGCC
        ); //deployNonce + 9

        gcc.allowlistPostConstructionContracts();

        vm.stopPrank();
        vm.startPrank(SIMON);

        vm.stopPrank();

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

    function test_guarded_buyOneShouldShouldEqualPointOneGlow() public {
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

    function test_guarded_BuyCCAuction() public {
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

        // console.log("gcc balance after purchase = ", gcc.balanceOf(operator));
        // // auction.logStateVariables();
        // console.log("new price per unit = ", auction.getPricePerUnit());
        // //add ten thousand more and warp 12 hours, and price should not change when we buy
        // sendGCCToAuction(10_000 ether);
        // // //12 hours
        // assert(gcc.balanceOf(operator) == 10_000 ether);
        // assert(auction.totalUnitsSold() == 10_000 ether / SALE_UNIT);
        // console.log("[1] price per unit = ", auction.getPricePerUnit());
        // vm.warp(block.timestamp + (3600 * 12));
        // uint256 unitsForSale = auction.unitsForSale();
        // console.log("total supply = ", auction.totalSupply());
        // assert(auction.totalSupply() == 10714285714285714285714);
        // assert(auction.totalSaleUnits() == auction.totalSupply() / SALE_UNIT);

        // console.log("units for sale = ", unitsForSale);
        // vm.startPrank(operator);
        // price = auction.getPricePerUnit();
        // auction.buyGCC({unitsToBuy: unitsForSale, maxPricePerUnit: price});
        // vm.stopPrank();

        // console.log("[2] gcc balance after purchase = ", gcc.balanceOf(operator));
        // // auction.logStateVariables();
        // console.log("[2] new price per unit = ", auction.getPricePerUnit());
        // //warp one week
        // vm.warp(block.timestamp + ONE_WEEK);
        // console.log("[3] new price per unit = ", auction.getPricePerUnit());
        // vm.warp(block.timestamp + ONE_WEEK);
        // console.log("[4] new price per unit = ", auction.getPricePerUnit());
        // vm.warp(block.timestamp + ONE_WEEK);
    }

    function test_guarded_receiveGCC_callerNotGCC_shouldRvert() public {
        vm.startPrank(address(0xdead));
        gcc.mint(address(auction), 1 ether);
        vm.expectRevert(CarbonCreditDutchAuction.CallerNotGCC.selector);
        auction.receiveGCC(1 ether);
        vm.stopPrank();
    }

    function test_guarded_buyGCC_buyingZeroUnits_shouldFail() public {
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

    function test_guarded_buyGCC_userPriceTooLow_shouldRevert() public {
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

    function test_guarded_buyGCC_overpurchasingGCC_shouldRevert() public {
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
