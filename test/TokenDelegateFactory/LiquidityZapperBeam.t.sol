// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenDelegateFactory} from "@/v2/TokenDelegateFactory.sol";
import {LiquidityZapperBeam} from "@/v2/beams/LiquidityZapperBeam.sol";
import {IUniswapV2Pair} from "@/interfaces/IUniswapV2Pair.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {USDG as USDGToken} from "@/USDG.sol";

interface IRouterFull is IUniswapRouterV2 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

contract LiquidityZapperBeamTest is Test {
    // Mainnet trader with a USDC balance (matches existing fork tests).
    address constant TRADER = 0x6884efd53b2650679996D3Ea206D116356dA08a9;

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant GLW = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);
    USDGToken constant USDG = USDGToken(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);
    IUniswapV2Pair constant PAIR = IUniswapV2Pair(0x6FA09ffC45F1dDC95c1bc192956717042f142c5d);
    IRouterFull constant ROUTER = IRouterFull(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    TokenDelegateFactory factory;
    LiquidityZapperBeam beam;

    address endowment = address(0xE1D0);

    event Zapped(
        address indexed endowment,
        uint256 usdgIn,
        uint256 usdgSwapped,
        uint256 glwReceived,
        uint256 usdgReserveAfterSwap,
        uint256 glwReserveAfterSwap,
        uint256 lpMinted
    );

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"));
        factory = new TokenDelegateFactory();
        beam = new LiquidityZapperBeam();
    }

    function _ensureUSDG(address who, uint256 amount) internal {
        if (USDG.balanceOf(who) >= amount) return;
        uint256 rem = amount - USDG.balanceOf(who);
        vm.startPrank(who);
        USDC.approve(address(USDG), rem);
        USDG.swap(who, rem);
        vm.stopPrank();
    }

    function _toks1(address t) internal pure returns (address[] memory a) {
        a = new address[](1);
        a[0] = t;
    }

    function _amts1(uint256 v) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = v;
    }

    /// @dev Quote `minGlwOut` the same way the offchain caller would: ask the
    /// router for the swap output at the optimal split, then haircut 1%.
    function _quoteMinGlwOut(uint256 usdgIn) internal view returns (uint256 swapAmount, uint256 minGlwOut) {
        bool usdgIs0 = address(USDG) < address(GLW);
        (uint256 r0, uint256 r1,) = PAIR.getReserves();
        uint256 reserveUsdg = usdgIs0 ? r0 : r1;

        uint256 mag = 1e24;
        swapAmount = beam.findOptimalAmountToSwap(usdgIn * mag, reserveUsdg * mag) / mag;

        address[] memory path = new address[](2);
        path[0] = address(USDG);
        path[1] = address(GLW);
        uint256[] memory amounts = ROUTER.getAmountsOut(swapAmount, path);
        minGlwOut = amounts[1] * 99 / 100;
    }

    function test_zap_credits_endowment_with_LP() public {
        uint256 usdgIn = 100 * 1e6; // 100 USDG
        _ensureUSDG(TRADER, usdgIn);

        (, uint256 minGlwOut) = _quoteMinGlwOut(usdgIn);

        uint256 lpBefore = IERC20(address(PAIR)).balanceOf(endowment);
        uint256 traderUsdgBefore = USDG.balanceOf(TRADER);

        bytes memory beamData = abi.encodeCall(LiquidityZapperBeam.cast, (endowment, minGlwOut, 0));

        vm.startPrank(TRADER);
        USDG.approve(address(factory), usdgIn);
        address executor = factory.exec(_toks1(address(USDG)), _amts1(usdgIn), address(beam), beamData);
        vm.stopPrank();

        // Trader paid full amount.
        assertEq(traderUsdgBefore - USDG.balanceOf(TRADER), usdgIn, "trader debited usdgIn");

        // Endowment received LP.
        uint256 lpDelta = IERC20(address(PAIR)).balanceOf(endowment) - lpBefore;
        assertGt(lpDelta, 0, "endowment received zero LP");

        // Executor (counterfactual wallet) is empty after dust sweep.
        assertEq(USDG.balanceOf(executor), 0, "no USDG dust at executor");
        assertEq(GLW.balanceOf(executor), 0, "no GLW dust at executor");
        assertEq(IERC20(address(PAIR)).balanceOf(executor), 0, "no LP dust at executor");
    }

    function test_zap_emits_Zapped_and_reserves_balance() public {
        uint256 usdgIn = 50 * 1e6;
        _ensureUSDG(TRADER, usdgIn);

        bool usdgIs0 = address(USDG) < address(GLW);
        uint256 reserveUsdgPre;
        uint256 reserveGlwPre;
        {
            (uint256 r0, uint256 r1,) = PAIR.getReserves();
            reserveUsdgPre = usdgIs0 ? r0 : r1;
            reserveGlwPre = usdgIs0 ? r1 : r0;
        }

        (, uint256 minGlwOut) = _quoteMinGlwOut(usdgIn);
        bytes memory beamData = abi.encodeCall(LiquidityZapperBeam.cast, (endowment, minGlwOut, 0));

        vm.startPrank(TRADER);
        USDG.approve(address(factory), usdgIn);

        // Topic-only check: confirm a Zapped event was emitted for `endowment`.
        vm.expectEmit(true, false, false, false);
        emit Zapped(endowment, 0, 0, 0, 0, 0, 0);
        factory.exec(_toks1(address(USDG)), _amts1(usdgIn), address(beam), beamData);
        vm.stopPrank();

        // The optimal-zap math means: GLW that left via swap equals GLW that
        // came back via addLiquidity, so the GLW reserve returns to its pre
        // level (modulo a wei or two of integer rounding). USDG reserve grows
        // by ~usdgIn, less any USDG dust swept to endowment.
        (uint256 r0Post, uint256 r1Post,) = PAIR.getReserves();
        uint256 reserveUsdgPost = usdgIs0 ? r0Post : r1Post;
        uint256 reserveGlwPost = usdgIs0 ? r1Post : r0Post;

        assertApproxEqAbs(reserveGlwPost, reserveGlwPre, 1, "GLW reserve unchanged net");
        // USDG growth must be <= usdgIn (some may be left as dust → endowment),
        // and within 1% of usdgIn given the formula's tight rounding.
        uint256 usdgGrowth = reserveUsdgPost - reserveUsdgPre;
        assertLe(usdgGrowth, usdgIn, "USDG reserve growth bounded by input");
        assertGe(usdgGrowth, usdgIn * 99 / 100, "USDG reserve growth within 1% of input");
    }

    function test_zap_reverts_when_minGlwOut_too_high() public {
        uint256 usdgIn = 25 * 1e6;
        _ensureUSDG(TRADER, usdgIn);

        (, uint256 minGlwOut) = _quoteMinGlwOut(usdgIn);
        uint256 unrealistic = minGlwOut * 2; // demand 2x what's actually achievable

        bytes memory beamData = abi.encodeCall(LiquidityZapperBeam.cast, (endowment, unrealistic, 0));

        vm.startPrank(TRADER);
        USDG.approve(address(factory), usdgIn);
        // Router reverts with "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT" — bubbled
        // through the executor's delegatecall, then the factory.
        vm.expectRevert();
        factory.exec(_toks1(address(USDG)), _amts1(usdgIn), address(beam), beamData);
        vm.stopPrank();
    }

    function test_zap_reverts_on_minLpOut() public {
        uint256 usdgIn = 25 * 1e6;
        _ensureUSDG(TRADER, usdgIn);

        (, uint256 minGlwOut) = _quoteMinGlwOut(usdgIn);
        uint256 unrealisticLp = type(uint256).max;

        bytes memory beamData = abi.encodeCall(LiquidityZapperBeam.cast, (endowment, minGlwOut, unrealisticLp));

        vm.startPrank(TRADER);
        USDG.approve(address(factory), usdgIn);
        vm.expectRevert(); // InsufficientLpOut(lpMinted, type(uint256).max)
        factory.exec(_toks1(address(USDG)), _amts1(usdgIn), address(beam), beamData);
        vm.stopPrank();
    }

    function test_zap_reverts_when_no_USDG_pre_funded() public {
        // Skip the factory entirely: call beam directly via a manually crafted
        // executor-style flow. Easier path: call factory.exec with amount 0.
        // Factory will call safeTransferFrom for 0 (no-op), beam reads
        // balance == 0 and reverts NoUSDG.
        bytes memory beamData = abi.encodeCall(LiquidityZapperBeam.cast, (endowment, 0, 0));

        vm.prank(TRADER);
        vm.expectRevert(LiquidityZapperBeam.NoUSDG.selector);
        factory.exec(_toks1(address(USDG)), _amts1(0), address(beam), beamData);
    }
}
