// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {Handler} from "./handlers/Handler.t.sol";
import {MockUSDCTax} from "@/testing/MockUSDCTax.sol";
import {EarlyLiquidityMockMinerPool} from "@/testing/EarlyLiquidity/EarlyLiquidityMockMinerPool.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Holding, ClaimHoldingArgs, IHoldingContract, HoldingContract} from "@/HoldingContract.sol";

contract EarlyLiquidityTest is Test {
    //-----------------CONSTANTS-----------------
    address public constant SIMON = address(0x11241998);
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant VESTING_CONTRACT = address(0x5);
    uint256 public constant USDC_DECIMALS = 6;
    uint256 constant POINT_6_USDC = 6 * (10 ** (USDC_DECIMALS - 1));
    uint256 public constant MAX_PRICE_EVER = POINT_6_USDC * 4096;

    //-----------------CONTRACTS-----------------
    TestGLOW public glw;
    EarlyLiquidity public earlyLiquidity;
    MockUSDC usdc;
    Handler handler;
    EarlyLiquidityMockMinerPool minerPool;
    TestGLOW glow;
    HoldingContract holdingContract;
    address vetoCouncilAddress = address(0x49349031419);

    //-----------------SETUP-----------------
    function setUp() public {
        usdc = new MockUSDC();
        holdingContract = new HoldingContract(vetoCouncilAddress);
        earlyLiquidity = new EarlyLiquidity(address(usdc),address(holdingContract));
        glow = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
        minerPool = new EarlyLiquidityMockMinerPool(address(earlyLiquidity),address(glow),address(usdc),
        address(holdingContract));
        earlyLiquidity.setMinerPool(address(minerPool));
        glw = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
        handler = new Handler(address(earlyLiquidity), address(usdc));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IEarlyLiquidity.buy.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetSelector(fs);
        targetContract(address(handler));
    }

    //-----------------INVARIANTS-----------------
    function invariant_earlyLiquidityShouldNeverHaveMoreThan12Mil() public {
        assertTrue(glw.balanceOf(address(earlyLiquidity)) <= 12_000_000 ether);
    }

    function invariant_priceShouldNeverBeGreaterThanMaxPrice() public {
        uint256 totalSold = earlyLiquidity.totalSold() / 1e18;
        if (totalSold == 12_000_000) {
            return;
        }
        uint256 tokensLeftToReach12Mil = 12_000_000 - totalSold;
        uint256 price = earlyLiquidity.getCurrentPrice();
        assertTrue(price <= MAX_PRICE_EVER);

        //We should never be paying more than 4096 times the starting price per token
        //If we do, we know something went wrong.
        uint256 priceToReachMax = earlyLiquidity.getPrice(tokensLeftToReach12Mil);
        assertTrue(priceToReachMax <= MAX_PRICE_EVER * tokensLeftToReach12Mil);
    }

    //-----------------TESTS-----------------

    /**
     * @dev we set glow and check that glw correctly minted 12 million tokens
     * @dev we also send 1 billion * 1e12 USDC to SIMON to buy GLOW with
     * @dev this function is used in other tests to stage the contract
     */
    function test_setGlowAndMint() public {
        earlyLiquidity.setGlowToken(address(glw));
        assertEq(glw.balanceOf(address(earlyLiquidity)), 12_000_000 ether);
        usdc.mint(SIMON, 1_000_000_000 ether);
    }

    function test_buyAllInEL() public {
        test_setGlowAndMint();
        vm.startPrank(SIMON);
        uint256 incrementsToPurchase = earlyLiquidity.TOTAL_INCREMENTS_TO_SELL();
        uint256 price = earlyLiquidity.getPrice(incrementsToPurchase);
        usdc.mint(SIMON, price);
        usdc.approve(address(earlyLiquidity), price);
        earlyLiquidity.buy(incrementsToPurchase, price);
        vm.stopPrank();
    }

    /**
     * @dev we test that purchasing glow should
     *         -   increase the total sold
     *         -   increase the glw balance of the buyer by the amount bought
     *         -   decrease the usdc balance of the buyer by the amount spent
     *         -   the price increases after the purchase
     * @dev for more comprehensive tests regarding pricing, see the EarlyLiquidityTest.ts file in this folder
     */
    function test_Buy() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 400,000 tokens (max increments)
        //400,000 million tokens = 40_000_000 increments of .01
        uint256 incrementsToPurchase = 40_000_000;
        uint256 totalCost = earlyLiquidity.getPrice(incrementsToPurchase);
        usdc.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);
        uint256 usdcBalanceBefore = usdc.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = usdc.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(incrementsToPurchase, totalCost);

        uint256 glwBalanceAfter = glw.balanceOf(SIMON);
        uint256 usdcBalanceAfter = usdc.balanceOf(SIMON);

        assertEq(earlyLiquidity.totalSold(), 400_000 ether);
        assertEq(glwBalanceAfter, 400_000 ether);
        assertEq(usdcBalanceAfter, usdcBalanceBefore - totalCost);

        uint256 totalCost2 = earlyLiquidity.getPrice(incrementsToPurchase);

        assertTrue(totalCost2 > totalCost);

        vm.stopPrank();
    }

    function test_noPriceShouldEverRevert() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 400,000 tokens (max increments)
        //400,000 million tokens = 40_000_000 increments of .01
        uint256 incrementsToPurchase = 40_000_000;
        usdc.approve(address(earlyLiquidity), 1_000_000_000);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);

        //12 million tokens / 400,000 max per tx = 30
        for (uint256 i; i < 30; ++i) {
            uint256 totalCost = earlyLiquidity.getPrice(incrementsToPurchase);
            usdc.mint(SIMON, totalCost);
            usdc.approve(address(earlyLiquidity), totalCost);
            earlyLiquidity.buy(incrementsToPurchase, totalCost);
        }

        uint256 totalSold = earlyLiquidity.totalSold();
        assertEq(totalSold, 1e18 * 12_000_000);
        //Make sure buying one more token will revert
        vm.expectRevert(IEarlyLiquidity.AllSold.selector);
        uint256 price = earlyLiquidity.getPrice(1);
        usdc.mint(SIMON, price);
        usdc.approve(address(earlyLiquidity), price);
        vm.expectRevert(IEarlyLiquidity.AllSold.selector);
        earlyLiquidity.buy(1, price);

        assertEq(glw.balanceOf(address(earlyLiquidity)), 0);
        assertEq(glw.balanceOf(SIMON), 12_000_000 ether);

        vm.stopPrank();
    }

    /**
     * @dev we test to make sure that usdc used to buy goes to the
     *             - miner pool contract
     */
    function test_Buy_checkUSDCGoesToHoldingContract() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 400,000 tokens (max increments)
        uint256 incrementsToPurchase = 40_000_000;
        uint256 totalCost = earlyLiquidity.getPrice(incrementsToPurchase);
        usdc.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);

        uint256 holdingContractBalanceBefore = usdc.balanceOf(address(holdingContract));
        uint256 usdcBalanceBefore = usdc.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = usdc.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(incrementsToPurchase, totalCost);

        uint256 glwBalanceAfter = glw.balanceOf(SIMON);
        uint256 usdcBalanceAfter = usdc.balanceOf(SIMON);
        uint256 holdingContractBalanceAfter = usdc.balanceOf(address(holdingContract));

        assertEq(earlyLiquidity.totalSold(), 400_000 ether);

        uint256 amountReceivedFromELInMP = minerPool.grcDepositFromEarlyLiquidity();
        assertEq(amountReceivedFromELInMP, holdingContractBalanceAfter - holdingContractBalanceBefore);

        assertTrue(holdingContractBalanceAfter - totalCost == holdingContractBalanceBefore);
    }

    /**
     * @dev we replicate the logic above but assuming USDC has
     *         - implemented a tax
     * @dev - the amount sent to the miner pool contract through {donateToGRCMinerRewardsPoolEarlyLiquidity}
     *        - should be equal to the total amount that got sent even with an unforseen tax
     */
    function test_Buy_checkUSDCGoesToMinerPool_taxToken() public {
        vm.startPrank(SIMON);
        MockUSDCTax taxUsdc = new MockUSDCTax();
        uint256 increments = 40_000_000;
        taxUsdc.mint(SIMON, 1_000_000_000 ether);
        holdingContract = new HoldingContract(vetoCouncilAddress);
        earlyLiquidity = new EarlyLiquidity(address(taxUsdc),address(holdingContract));
        glow = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
        earlyLiquidity.setGlowToken(address(glow));
        minerPool = new EarlyLiquidityMockMinerPool(address(earlyLiquidity),address(glow),address(taxUsdc),
        address(holdingContract));
        earlyLiquidity.setMinerPool(address(minerPool));

        uint256 totalCost = earlyLiquidity.getPrice(increments);
        taxUsdc.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);

        uint256 holdingContractBalanceBefore = taxUsdc.balanceOf(address(holdingContract));
        uint256 usdcBalanceBefore = taxUsdc.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = taxUsdc.allowance(address(this), address(earlyLiquidity));

        taxUsdc.approve(address(earlyLiquidity), totalCost);
        earlyLiquidity.buy(increments, totalCost);

        uint256 glwBalanceAfter = glw.balanceOf(SIMON);
        uint256 usdcBalanceAfter = taxUsdc.balanceOf(SIMON);
        uint256 holdingContractBalanceAfter = taxUsdc.balanceOf(address(holdingContract));

        assertEq(earlyLiquidity.totalSold(), 400_000 ether);

        uint256 amountReceivedFromELInMP = minerPool.grcDepositFromEarlyLiquidity();
        assertEq(amountReceivedFromELInMP, holdingContractBalanceAfter - holdingContractBalanceBefore);
        assertTrue(amountReceivedFromELInMP != totalCost);
    }

    /**
     * @dev we test that if the user input maxCost is too low, the transaction should revert
     */
    function test_Buy_priceTooHigh_shouldFail() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1_000_000 * .01 = 10_000  tokens
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdc.approve(address(earlyLiquidity), totalCost);
        vm.expectRevert(IEarlyLiquidity.PriceTooHigh.selector);
        earlyLiquidity.buy(1_000_000, totalCost - 1);
    }

    /**
     * @dev we test that once Glow is set, it cannot be set again
     */
    function test_setGlowTokenTwice_shouldFail() public {
        test_setGlowAndMint();

        vm.expectRevert("Glow token already set");
        earlyLiquidity.setGlowToken(address(glw));
    }

    /**
     * @dev we test that the starting price should be 0.6 (6 * 1e5) USDC
     */
    function test_getCurrentPrice() public {
        test_setGlowAndMint();
        //starting price should be 60 cents
        uint256 currentPrice = earlyLiquidity.getCurrentPrice();
        console.log("current price", currentPrice);
        bool withinRange = fallsWithinRange(currentPrice, POINT_6_USDC / 100, 1);
        assertTrue(withinRange);
    }

    function test_simonCustom() public {
        console.log("price = ", earlyLiquidity.getPrice(100));

        //55609618602381372
    }
    //-----------------UTILS-----------------

    function fallsWithinRange(uint256 a, uint256 b, uint256 range) public pure returns (bool) {
        return a >= b - range && a <= b + range;
    }
}
