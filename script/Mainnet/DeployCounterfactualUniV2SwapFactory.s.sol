// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CounterfactualUniV2SwapFactory} from "@/v2/CounterfactualUniV2SwapFactory.sol";

contract DeployCounterfactualUniV2SwapFactory is Script {
    function run() external {
        vm.startBroadcast();

        CounterfactualUniV2SwapFactory factory = new CounterfactualUniV2SwapFactory();
        console.log("CounterfactualUniV2SwapFactory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
