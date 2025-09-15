// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "@/testing/MockERC20.sol";
import {Forwarder} from "@/Forwarder.sol";
import {USDG} from "@/USDG.sol";
import {CounterfactualHolderFactory} from "@/v2/CounterfactualHolderFactory.sol";

/*

  [1653211] → new CounterfactualHolderFactory@0x52ad78446eb4066F729034825cE9765997C297a7
    └─ ← [Return] 8147 bytes of code

  [804746] → new Forwarder@0xD487240a9Cc032Dc5CC092F2Bbe2C19aCD583eef
    └─ ← [Return] 3906 bytes of code
    */
    
contract DeployForwarder is Test, Script {
    function run() external {
        vm.startBroadcast();
        CounterfactualHolderFactory cfhFactory = new CounterfactualHolderFactory();
        USDG usdg = USDG(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);
        IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        new Forwarder(usdg, usdc, cfhFactory);
        vm.stopBroadcast();
    }
}
