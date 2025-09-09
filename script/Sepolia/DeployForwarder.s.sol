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

contract DeployForwarder is Test, Script {
    function run() external {
        vm.startBroadcast();
        MockUSDC usdc = new MockUSDC();
        USDG usdg = new USDG({
            _usdc: address(usdc),
            _usdcReceiver: address(this),
            _owner: address(this),
            _univ2Factory: address(this),
            _glow: address(this),
            _gcc: address(this),
            _holdingContract: address(this),
            _vetoCouncilContract: address(this),
            _impactCatalyst: address(this)
        });
        CounterfactualHolderFactory cfhFactory = new CounterfactualHolderFactory();
        Forwarder forwarder = new Forwarder({
            _usdg: USDG(0x2a085A3aEA8982396533327c854753Ce521B666d),
            _usdc: IERC20(0x93C898be98cD2618bA84a6dccF5003d3bBE40356),
            _cfhFactory: cfhFactory
        });
        vm.stopBroadcast();
    }
}
