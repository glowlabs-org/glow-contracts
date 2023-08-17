// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";

contract EarlyLiquidityTest is Test {
    TestGLOW public glw;
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    EarlyLiquidity public earlyLiquidity;
    MockUSDC usdc;
    address public constant VESTING_CONTRACT = address(0x5);
    uint256 public constant USDC_DECIMALS = 6;
    uint256 constant POINT_6_USDC = 6 * (10 ** (USDC_DECIMALS - 1));

    //Manually inlining IGlow events until  0.8.22 release...
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimUnstakedGLW(address indexed user, uint256 amount);

    function _fallsWithinBounds(uint256 actual, uint256 lowerBound, uint256 upperBound) internal pure returns (bool) {
        return actual >= lowerBound && actual <= upperBound;
    }

    function setUp() public {
        usdc = new MockUSDC();
        earlyLiquidity = new EarlyLiquidity(address(usdc));
        glw = new TestGLOW(address(earlyLiquidity),VESTING_CONTRACT);
    }

    function test_setGlowAndMint() public {
        earlyLiquidity.setGlowToken(address(glw));
        assertEq(glw.balanceOf(address(earlyLiquidity)), 12_000_000 ether);
        usdc.mint(SIMON, 1_000_000_000 ether);
    }

    function test_ShouldHave12MillionTokensOnConstruction() public {
        test_setGlowAndMint();

        assertEq(glw.balanceOf(address(earlyLiquidity)), 12_000_000 ether);
    }

    function test_getPrice() public {
        test_setGlowAndMint();

        //starting price should be 60 cents
        // assertEq(earlyLiquidity.getPrice(0), POINT_6_USDC);
        uint256 price = earlyLiquidity.getPrice(0);
        console.log("price = ", price);

        price = earlyLiquidity.getPrice(2);
        console.log("price = ", price);

        price = earlyLiquidity.getPrice(12_000_000);
        console.log("price = ", price);

        //TODO: best thing to do is precompute a bunch of values
        //and then assertEq that they fall into a certain range

        //
    }

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
        console.log("glwBalanceAfter = ", glwBalanceAfter);
        console.log("usdcBalanceAfter = ", usdcBalanceAfter);

        assertEq(earlyLiquidity.totalSold(), 1_000_000 ether);

        uint256 totalCost2 = earlyLiquidity.getPrice(1_000_000);

        assertTrue(totalCost2 > totalCost);
    }

    function test_Buy_priceTooHigh_shouldFail() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        uint256 totalCost2 = earlyLiquidity.getPrice(1_000_000 + 1);
        assertTrue(totalCost2 > totalCost);
        usdc.approve(address(earlyLiquidity), totalCost);
        vm.expectRevert(IEarlyLiquidity.PriceTooHigh.selector);
        earlyLiquidity.buy(1_000_000 * 1e18, totalCost - 1);
    }

    function test_Buy_modNotZeroShouldFail() public {
        test_setGlowAndMint();

        vm.startPrank(SIMON);
        //buy 1 million token
        uint256 totalCost = earlyLiquidity.getPrice(1_000_000);
        usdc.approve(address(earlyLiquidity), totalCost);
        vm.expectRevert(IEarlyLiquidity.ModNotZero.selector);
        earlyLiquidity.buy(1_000_000 * 1e18 - 1, totalCost + 1);
    }

    function test_setGlowTokenTwice_shouldFail() public {
        test_setGlowAndMint();

        vm.expectRevert("Glow token already set");
        earlyLiquidity.setGlowToken(address(glw));
    }

    function test_getCurrentPrice() public {
        test_setGlowAndMint();

        //starting price should be 60 cents
        assertEq(earlyLiquidity.getCurrentPrice(), POINT_6_USDC);
    }

    function test_findPriceFromAmount() public {
        //should be  zero tokens
        // uint amount = earlyLiquidity.getAmountFromDesiredPrice(0, POINT_6_USDC);
        // console.log("amount = ",amount);
        // // assertEq(amount, 0);

        // // //.90 cents should be 500_000 tokens
        // // amount = earlyLiquidity.getAmountFromDesiredPrice(0, POINT_6_USDC*3/2);
        // // assertEq(amount, 500_000 * (10 ** USDC_DECIMALS));

        // //90 cents should be 1_000_000 tokens
        // amount = earlyLiquidity.getAmountFromDesiredPrice(0, POINT_6_USDC * 3/2);
        // console.log("amount = ",amount);
        // assertEq(amount, 1_000_000 * (10 ** USDC_DECIMALS));

        //2.4 should be 2_000_000 tokens
        // amount = earlyLiquidity.getAmountFromDesiredPrice(0, POINT_6_USDC * 4);
    }

    // function testFuzz_pricesFormulasShouldMatch(uint price) public {
    //     vm.assume(price > POINT_6_USDC && price < POINT_6_USDC * 4096);
    //     uint amount = earlyLiquidity.getAmountFromDesiredPrice(0, price);
    //     uint actualPrice = earlyLiquidity.getPrice(amount);
    //     //.000001 , in case of division errors
    //     int256 allowedVariance = 1;
    //     int256 diff = int256(actualPrice) - int256(price);
    //     assertTrue(diff <= allowedVariance);
    // }

    // function test_purchaseGLOW() public {
    //     //I want to buy 1_000_000 tokens
    //     uint price = getPrice(1_000_000 ether);
    // }
}
