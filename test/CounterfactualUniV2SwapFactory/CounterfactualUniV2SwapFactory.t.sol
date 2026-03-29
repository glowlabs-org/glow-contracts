// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CounterfactualUniV2SwapFactory} from "@/v2/CounterfactualUniV2SwapFactory.sol";
import {CounterfactualHolderFactory} from "@/v2/CounterfactualHolderFactory.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {USDG as USDGToken} from "@/USDG.sol";

interface IUniswapV2RouterFull is IUniswapRouterV2 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

contract CounterfactualUniV2SwapFactoryTest is Test {
    address constant TRADER = 0x6884efd53b2650679996D3Ea206D116356dA08a9;

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant GLOW = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);
    USDGToken constant USDG = USDGToken(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);

    CounterfactualHolderFactory constant CFH_FACTORY =
        CounterfactualHolderFactory(0x5bB7eC88cA80146FF47019079Cf0330532A1157F);
    IUniswapV2RouterFull constant ROUTER = IUniswapV2RouterFull(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    CounterfactualUniV2SwapFactory factory;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"));
        factory = new CounterfactualUniV2SwapFactory();
    }

    /// @dev Swap USDG -> GLOW; check the recipient's CFH wallet receives at least amountOutMin GLOW.
    function test_swapUSDGForGLOW() public {
        uint256 amountIn = 10 * 1e6; // 10 USDG

        if (USDG.balanceOf(TRADER) < amountIn) {
            uint256 rem = amountIn - USDG.balanceOf(TRADER);
            vm.startPrank(TRADER);
            USDC.approve(address(USDG), amountIn);
            USDG.swap(TRADER, rem);
            vm.stopPrank();
        }

        address[] memory path = new address[](2);
        path[0] = address(USDG);
        path[1] = address(GLOW);

        uint256[] memory expectedAmounts = ROUTER.getAmountsOut(amountIn, path);
        uint256 amountOutMin = expectedAmounts[1] * 99 / 100; // 1% slippage

        uint256 cfhBefore = CFH_FACTORY.balanceOfCFH(TRADER, address(GLOW));

        vm.startPrank(TRADER);
        USDG.approve(address(factory), amountIn);
        factory.exec(amountIn, amountOutMin, path, TRADER, block.timestamp + 1 hours);
        vm.stopPrank();

        uint256 cfhAfter = CFH_FACTORY.balanceOfCFH(TRADER, address(GLOW));
        assertGe(cfhAfter - cfhBefore, amountOutMin, "CFH GLOW balance did not meet amountOutMin");
    }

    /// @dev path[0] = USDC is converted 1:1 to USDG inside the swap contract before the AMM hop.
    ///      Checks that USDC is correctly routed through USDG and the CFH wallet receives GLOW.
    function test_swapUSDCForGLOW_convertsToUSDG() public {
        uint256 amountIn = 10 * 1e6; // 10 USDC

        // deal(address(USDC), TRADER, amountIn);

        // Quote using USDG->GLOW since USDC is converted 1:1 to USDG before the swap
        address[] memory quotePathUsdg = new address[](2);
        quotePathUsdg[0] = address(USDG);
        quotePathUsdg[1] = address(GLOW);
        uint256[] memory expectedAmounts = ROUTER.getAmountsOut(amountIn, quotePathUsdg);
        uint256 amountOutMin = expectedAmounts[1] * 99 / 100;

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(GLOW);

        uint256 cfhBefore = CFH_FACTORY.balanceOfCFH(TRADER, address(GLOW));

        vm.startPrank(TRADER);
        USDC.approve(address(factory), amountIn);
        factory.exec(amountIn, amountOutMin, path, TRADER, block.timestamp + 1 hours);
        vm.stopPrank();

        uint256 cfhAfter = CFH_FACTORY.balanceOfCFH(TRADER, address(GLOW));
        assertGe(
            cfhAfter - cfhBefore, amountOutMin, "CFH GLOW balance did not meet amountOutMin after USDC->USDG->GLOW"
        );
    }
}
