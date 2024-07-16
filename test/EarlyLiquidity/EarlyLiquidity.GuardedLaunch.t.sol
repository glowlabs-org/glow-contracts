// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "forge-std/console.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {Handler} from "./handlers/Handler.GuardedLaunch.t.sol";
import {MockUSDCTax} from "@/testing/MockUSDCTax.sol";
import {EarlyLiquidityMockMinerPool} from "@/testing/EarlyLiquidity/EarlyLiquidityMockMinerPool.sol";
import {TestGLOWGuardedLaunch} from "@/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";

contract EarlyLiquidityGuardedLaunchTest is Test {
    //-----------------CONSTANTS-----------------
    address public constant SIMON = address(0x11241998);
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant VESTING_CONTRACT = address(0x5);
    uint256 public constant USDC_DECIMALS = 6;
    uint256 constant STARTING_USDC_PRICE = 3 * (10 ** (USDC_DECIMALS - 1)); //.1
    uint256 public constant MAX_PRICE_EVER = STARTING_USDC_PRICE * 4096;
    address mockImpactCatalyst = address(0x12339182938aa19389128);
    address mockGCC = address(0x12339182938aaffffff19389128);
    //-----------------CONTRACTS-----------------
    TestGLOWGuardedLaunch public glw;
    EarlyLiquidity public earlyLiquidity;
    MockUSDC usdc;
    Handler handler;
    EarlyLiquidityMockMinerPool minerPool;
    TestGLOWGuardedLaunch glow;
    SafetyDelay holdingContract;
    TestUSDG public usdg;
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    FakeGCC public gcc;
    address vetoCouncilAddress = address(0x49349031419);
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);

    address deployer = tx.origin;
    address notDeployer = address(0x123123);
    //-----------------SETUP-----------------

    function setUp() public {
        vm.startPrank(notDeployer);
        uniswapFactory = new UnifapV2Factory();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        weth = new WETH9();
        gcc = new FakeGCC();
        vm.stopPrank();
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedMinerPool = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputeEarlyLiquidity = computeCreateAddress(deployer, deployerNonce + 4);
        usdc = new MockUSDC(); //deployerNonce
        glow = new TestGLOWGuardedLaunch(
            address(precomputeEarlyLiquidity),
            VESTING_CONTRACT,
            precomputedMinerPool,
            VETO_COUNCIL,
            GRANTS_TREASURY,
            SIMON,
            address(precomputedUSDG),
            address(uniswapFactory),
            address(gcc)
        ); //   deployerNonce + 1
        //TODO: left off here, adjust the deploy nonces and pre-compute
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _gcc: address(gcc),
            _glow: address(glow),
            _holdingContract: address(precomputedHoldingContract),
            _vetoCouncilContract: vetoCouncilAddress,
            _impactCatalyst: mockImpactCatalyst
        }); //deployerNonce + 2

        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedMinerPool); //deployerNonce + 3
        earlyLiquidity =
            new EarlyLiquidity(address(usdg), address(holdingContract), precomputedGlow, precomputedMinerPool); //deployerNonce + 4
        minerPool = new EarlyLiquidityMockMinerPool(
            address(earlyLiquidity), address(glow), address(usdc), address(holdingContract)
        ); //deployerNonce + 5

        glw = new TestGLOWGuardedLaunch(
            address(earlyLiquidity),
            VESTING_CONTRACT,
            address(minerPool),
            VETO_COUNCIL,
            GRANTS_TREASURY,
            SIMON,
            address(usdg),
            address(uniswapFactory),
            address(gcc)
        );
        handler = new Handler(address(earlyLiquidity), address(usdc), address(usdg));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IEarlyLiquidity.buy.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetSelector(fs);
        targetContract(address(handler));

        vm.stopPrank();

        vm.startPrank(usdgOwner);

        vm.stopPrank();
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
    function test_guarded_setGlowAndMint() public {
        assertEq(glw.balanceOf(address(earlyLiquidity)), 12_000_000 ether);
        vm.startPrank(SIMON);
        usdc.mint(SIMON, 1_000_000_000 ether);
        usdc.approve(address(usdg), 1_000_000_000 ether);
        usdg.swap(SIMON, 1_000_000_000 ether);
        vm.stopPrank();
    }

    function test_guarded_buyAllInEL() public {
        test_guarded_setGlowAndMint();
        vm.startPrank(SIMON);
        uint256 incrementsToPurchase = earlyLiquidity.TOTAL_INCREMENTS_TO_SELL();
        uint256 price = earlyLiquidity.getPrice(incrementsToPurchase);
        usdc.mint(SIMON, price);
        usdc.approve(address(usdg), price);
        usdg.swap(SIMON, price);
        usdg.approve(address(earlyLiquidity), price);
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
    function test_guarded_Buy_s() public {
        test_guarded_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 400,000 tokens (max increments)
        //400,000 million tokens = 40_000_000 increments of .01
        uint256 incrementsToPurchase = 40_000_000;
        uint256 totalCost = earlyLiquidity.getPrice(incrementsToPurchase);
        usdg.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);
        uint256 usdcBalanceBefore = usdg.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = usdc.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(incrementsToPurchase, totalCost);

        uint256 glwBalanceAfter = glow.balanceOf(SIMON);
        uint256 usdcBalanceAfter = usdg.balanceOf(SIMON);

        assertEq(earlyLiquidity.totalSold(), 400_000 ether);
        assertEq(glwBalanceAfter, 400_000 ether);
        assertEq(usdcBalanceAfter, usdcBalanceBefore - totalCost);

        uint256 totalCost2 = earlyLiquidity.getPrice(incrementsToPurchase);

        assertTrue(totalCost2 > totalCost);

        vm.stopPrank();
    }

    function test_guarded_noPriceShouldEverRevert() public {
        test_guarded_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 400,000 tokens (max increments)
        //400,000 million tokens = 40_000_000 increments of .01
        uint256 incrementsToPurchase = 40_000_000;
        usdg.approve(address(earlyLiquidity), 1_000_000_000);
        uint256 glwBalanceBefore = glw.balanceOf(SIMON);

        //12 million tokens / 400,000 max per tx = 30
        for (uint256 i; i < 30; ++i) {
            uint256 totalCost = earlyLiquidity.getPrice(incrementsToPurchase);
            usdc.mint(SIMON, totalCost);
            usdc.approve(address(usdg), totalCost);
            if (totalCost > 0) {
                usdg.swap(SIMON, totalCost);
            }
            usdg.approve(address(earlyLiquidity), totalCost);
            earlyLiquidity.buy(incrementsToPurchase, totalCost);
        }

        uint256 totalSold = earlyLiquidity.totalSold();
        assertEq(totalSold, 1e18 * 12_000_000);
        //Make sure buying one more token will revert
        vm.expectRevert(IEarlyLiquidity.AllSold.selector);
        uint256 price = earlyLiquidity.getPrice(1);
        usdc.mint(SIMON, price);
        usdc.approve(address(usdg), price);
        if (price > 0) {
            usdg.swap(SIMON, price);
        }
        usdg.approve(address(earlyLiquidity), price);
        vm.expectRevert(IEarlyLiquidity.AllSold.selector);
        earlyLiquidity.buy(1, price);

        assertEq(glow.balanceOf(address(earlyLiquidity)), 0);
        assertEq(glow.balanceOf(SIMON), 12_000_000 ether);

        vm.stopPrank();
    }

    /**
     * @dev we test to make sure that usdc used to buy goes to the
     *             - miner pool contract
     */
    function test_guarded_Buy_checkUSDCGoesToHoldingContract() public {
        test_guarded_setGlowAndMint();

        // vm.startPrank(usdgOwner);
        // usdg.setAllowlistedContracts({
        //     _glow: address(glw),
        //     _gcc: address(mockGCC),
        //     _holdingContract: address(holdingContract),
        //     _vetoCouncilContract: vetoCouncilAddress,
        //     _impactCatalyst: mockImpactCatalyst
        // });

        vm.startPrank(SIMON);

        //buy 400,000 tokens (max increments)
        uint256 incrementsToPurchase = 40_000_000;
        uint256 totalCost = earlyLiquidity.getPrice(incrementsToPurchase);
        usdg.approve(address(earlyLiquidity), totalCost);
        uint256 glwBalanceBefore = glow.balanceOf(SIMON);

        uint256 holdingContractBalanceBefore = usdg.balanceOf(address(holdingContract));
        uint256 usdcBalanceBefore = usdg.balanceOf(SIMON);
        assertEq(usdcBalanceBefore, 1_000_000_000 ether);
        assertEq(glwBalanceBefore, 0);
        uint256 allowance = usdg.allowance(address(this), address(earlyLiquidity));
        earlyLiquidity.buy(incrementsToPurchase, totalCost);

        uint256 glwBalanceAfter = glow.balanceOf(SIMON);
        uint256 usdcBalanceAfter = usdg.balanceOf(SIMON);
        uint256 holdingContractBalanceAfter = usdg.balanceOf(address(holdingContract));

        assertEq(earlyLiquidity.totalSold(), 400_000 ether);

        uint256 amountReceivedFromELInMP = minerPool.grcDepositFromEarlyLiquidity();
        assertEq(amountReceivedFromELInMP, holdingContractBalanceAfter - holdingContractBalanceBefore);

        assertTrue(holdingContractBalanceAfter - totalCost == holdingContractBalanceBefore);
        vm.stopPrank();
    }

    /**
     * @dev we test that if the user input maxCost is too low, the transaction should revert
     */
    function test_guarded_Buy_priceTooHigh_shouldFail() public {
        test_guarded_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1_000_000 * .01 = 10_000  tokens
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdg.approve(address(earlyLiquidity), totalCost);
        vm.expectRevert(IEarlyLiquidity.PriceTooHigh.selector);
        earlyLiquidity.buy(1_000_000, totalCost - 1);
    }

    function test_guarded_getCurrentPrice() public {
        test_guarded_setGlowAndMint();
        //starting price should be 30 cents
        uint256 currentPrice = earlyLiquidity.getCurrentPrice();
        console.log("current price", currentPrice);
        bool withinRange = fallsWithinRange(currentPrice, STARTING_USDC_PRICE / 100, 1);
        assertTrue(withinRange);
    }

    function test_guarded_simonCustom() public {
        console.log("price = ", earlyLiquidity.getPrice(100));

        //55609618602381372
    }
    //-----------------UTILS-----------------

    function fallsWithinRange(uint256 a, uint256 b, uint256 range) public pure returns (bool) {
        return a >= b - range && a <= b + range;
    }
}

contract FakeGCC {
    ICarbonCreditAuction public CARBON_CREDIT_AUCTION = ICarbonCreditAuction(address(0x1));
}
