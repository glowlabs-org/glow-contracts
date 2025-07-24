// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "@/testing/MockERC20.sol";
import {Forwarder} from "@/Forwarder.sol";

contract DeployForwarder is Test, Script {
    address private usdcForwarder = 0x5e230FED487c86B90f6508104149F087d9B1B0A7;

    function run() external {
        vm.startBroadcast();
        Forwarder forwarder = new Forwarder(usdcForwarder);
        vm.stopBroadcast();
    }
}
