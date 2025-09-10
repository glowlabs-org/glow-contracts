// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "@/testing/MockERC20.sol";
import {Forwarder} from "@/Forwarder.sol";
import {USDG} from "@/USDG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {USDG} from "@/USDG.sol";
import {CounterfactualHolderFactory} from "@/v2/CounterfactualHolderFactory.sol";
import {OffchainFractions} from "@/v2/OffchainFractions.sol";

contract DeployOffchainFractions is Test, Script {
    function run() external {
        vm.startBroadcast();

        CounterfactualHolderFactory cfhFactory = new CounterfactualHolderFactory();
        OffchainFractions offchainFractions = new OffchainFractions(cfhFactory);

        vm.stopBroadcast();
    }
}
