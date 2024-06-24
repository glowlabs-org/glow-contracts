// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

string constant fileToWriteTo = "deployedContractsGoerliGuardedLaunch.json";

contract SetLP is Test, Script {
    address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address uniswapV2Factory = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address usdcReceiver = address(0xfdafafdafafa124412f);

    address usdg = 0x7734720e7Cea67b29f53800C4aD5C40e61aBb645;
    address gcc = 0x71cEB276788c40D59E244087a1FBB185373aAB1A;

    function run() external {
        vm.startBroadcast();
        //add liquidity 1.1 gcc and 1.1 usdg

        IUniswapRouterV2 router = IUniswapRouterV2(uniswapV2Router);
        uint256 usdgAmount = 1.1 * 1e6;
        uint256 gccAmount = 1.1 ether;
        uint256 deadline = block.timestamp;

        //approve
        IERC20(usdg).approve(uniswapV2Router, usdgAmount);
        IERC20(gcc).approve(uniswapV2Router, gccAmount);

        //add liquidity
        router.addLiquidity(usdg, gcc, usdgAmount, gccAmount, usdgAmount, gccAmount, usdcReceiver, deadline);

        vm.stopBroadcast();
    }
}
