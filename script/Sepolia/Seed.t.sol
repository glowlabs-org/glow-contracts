// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "@/testing/MockERC20.sol";

string constant fileToWriteTo = "deployedContractsGoerliGuardedLaunch.json";

contract SeedScript is Test, Script {
    address uniswapV2Router = address(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3);

    MockERC20 glow = MockERC20(0x2655956673BF83aB40601dCbF3FEf08b5205bf5e);
    MockERC20 usdg = MockERC20(0x587E13Ba40d9AddeA28EEF4eF12e28DCa48C19b7);

    function run() external {
        vm.startBroadcast();
        address me = tx.origin;
        // //add liquidity 1.1 gcc and 1.1 usdg
        // glow = new MockERC20("glow", "GLW", 18);
        // usdg = new MockERC20("usdg", "USDG", 6);

        IUniswapRouterV2 router = IUniswapRouterV2(uniswapV2Router);
        // uint256 usdgAmount = 100_000_000 * 1e6;
        // uint256 glowAmount = 100_000_000 * 1e18;
        uint256 deadline = block.timestamp + 200000;

        // usdg.mint(me, usdgAmount);
        // glow.mint(me, glowAmount);
        // //approve
        // usdg.approve(uniswapV2Router, type(uint256).max);
        // glow.approve(uniswapV2Router, type(uint256).max);

        //add liquidity
        for (uint256 i; i < 500; ++i) {
            router.addLiquidity(
                address(usdg), address(glow), 1000 * 1e6, 1000 * 1e18, 1000 * 1e6, 1000 * 1e18, me, deadline
            );
        }

        vm.stopBroadcast();
    }
}
