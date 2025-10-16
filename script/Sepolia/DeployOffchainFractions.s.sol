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
import {Forwarder} from "@/Forwarder.sol";

contract DeployOffchainFractions is Test, Script {
    function run() external {
        vm.startBroadcast();

        CounterfactualHolderFactory cfhFactory = CounterfactualHolderFactory(0x2c3AB887746F6f4a8a4b9Db6aC800eb71945509A);
        OffchainFractions offchainFractions = new OffchainFractions(cfhFactory);
        Forwarder forwarder = new Forwarder({
            _usdg: USDG(0xda78313A3fF949890112c1B746AB1c75d1b1c17B),
            _usdc: IERC20(0x93C898be98cD2618bA84a6dccF5003d3bBE40356),
            _cfhFactory: cfhFactory
        });
        vm.stopBroadcast();
    }
}
