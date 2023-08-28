// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

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

    //-----------------SETUP-----------------
    function setUp() public {
        usdc = new MockUSDC();
        earlyLiquidity = new EarlyLiquidity(address(usdc));
        glow = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
        minerPool = new EarlyLiquidityMockMinerPool(address(earlyLiquidity),address(glow));
        earlyLiquidity.setMinerPool(address(minerPool));
        glw = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
        handler = new Handler(address(earlyLiquidity), address(usdc));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IEarlyLiquidity.buy.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
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
        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdc.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);
        uint256 usdcBalanceBefore = usdc.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = usdc.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(1_000_000 * 1e18, totalCost);

        uint256 glwBalanceAfter = glw.balanceOf(SIMON);
        uint256 usdcBalanceAfter = usdc.balanceOf(SIMON);

        assertEq(earlyLiquidity.totalSold(), 1_000_000 ether);
        assertEq(glwBalanceAfter, 1_000_000 ether);
        assertEq(usdcBalanceAfter, usdcBalanceBefore - totalCost);

        uint256 totalCost2 = earlyLiquidity.getPrice(1_000_000);

        assertTrue(totalCost2 > totalCost);
    }

    /**
     * @dev we test to make sure that usdc used to buy goes to the
     *             - miner pool contract
     */
    function test_Buy_checkUSDCGoesToMinerPool() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdc.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);

        uint256 minerPoolUsdcBalanceBefore = usdc.balanceOf(address(minerPool));
        uint256 usdcBalanceBefore = usdc.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = usdc.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(1_000_000 * 1e18, totalCost);

        uint256 glwBalanceAfter = glw.balanceOf(SIMON);
        uint256 usdcBalanceAfter = usdc.balanceOf(SIMON);
        uint256 minerPoolUsdcBalanceAfter = usdc.balanceOf(address(minerPool));

        assertEq(earlyLiquidity.totalSold(), 1_000_000 ether);

        uint256 totalCost2 = earlyLiquidity.getPrice(1_000_000);

        uint256 amountReceivedFromELInMP = minerPool.grcDepositFromEarlyLiquidity(address(usdc));
        assertEq(amountReceivedFromELInMP, minerPoolUsdcBalanceAfter - minerPoolUsdcBalanceBefore);

        assertTrue(totalCost2 > totalCost);
        assertTrue(minerPoolUsdcBalanceAfter - totalCost == minerPoolUsdcBalanceBefore);
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
        taxUsdc.mint(SIMON, 1_000_000_000 ether);
        earlyLiquidity = new EarlyLiquidity(address(taxUsdc));
        glow = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
        earlyLiquidity.setGlowToken(address(glow));
        minerPool = new EarlyLiquidityMockMinerPool(address(earlyLiquidity),address(glow));
        earlyLiquidity.setMinerPool(address(minerPool));

        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        taxUsdc.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);

        uint256 minerPoolUsdcBalanceBefore = taxUsdc.balanceOf(address(minerPool));
        uint256 usdcBalanceBefore = taxUsdc.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = taxUsdc.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(1_000_000 * 1e18, totalCost);

        uint256 glwBalanceAfter = glw.balanceOf(SIMON);
        uint256 usdcBalanceAfter = taxUsdc.balanceOf(SIMON);
        uint256 minerPoolUsdcBalanceAfter = taxUsdc.balanceOf(address(minerPool));

        assertEq(earlyLiquidity.totalSold(), 1_000_000 ether);

        uint256 totalCost2 = earlyLiquidity.getPrice(1_000_000);

        uint256 amountReceivedFromELInMP = minerPool.grcDepositFromEarlyLiquidity(address(taxUsdc));
        assertEq(amountReceivedFromELInMP, minerPoolUsdcBalanceAfter - minerPoolUsdcBalanceBefore);
        assertTrue(amountReceivedFromELInMP != totalCost);
        assertTrue(totalCost2 > totalCost);
    }

    /**
     * @dev we test that if the user input maxCost is too low, the transaction should revert
     */
    function test_Buy_priceTooHigh_shouldFail() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdc.approve(address(earlyLiquidity), totalCost);
        vm.expectRevert(IEarlyLiquidity.PriceTooHigh.selector);
        earlyLiquidity.buy(1_000_000 * 1e18, totalCost - 1);
    }

    /**
     * @dev users can only buy in increments of 1e18 tokens due to the floating point math
     * @dev we test that if the user input amount is not a multiple of 1e18, the transaction should revert
     */
    function test_Buy_modNotZeroShouldFail() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdc.approve(address(earlyLiquidity), totalCost);
        vm.expectRevert(IEarlyLiquidity.ModNotZero.selector);
        earlyLiquidity.buy(1_000_000 * 1e18 - 1, totalCost + 1);
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
        bool withinRange = fallsWithinRange(earlyLiquidity.getCurrentPrice(), POINT_6_USDC, 1);
        assertTrue(withinRange);
    }

    /**
     * @dev we test that querying any price above the 12 millionth token should revert
     */
    function test_getCurrentPrice_moreThan12MilTokens_shouldRevert() public {
        test_setGlowAndMint();
        vm.expectRevert(IEarlyLiquidity.AllSold.selector);
        earlyLiquidity.getPrice(12_000_000 + 1);
    }

    //-----------------UTILS-----------------
    function fallsWithinRange(uint256 a, uint256 b, uint256 range) public pure returns (bool) {
        return a >= b - range && a <= b + range;
    }
}
