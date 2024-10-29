// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Multicall3} from "./Multicall3.sol";

contract DeployMulticall3 is Script {
    function run() public {
        vm.startBroadcast();

        Multicall3 m = new Multicall3();

        vm.stopBroadcast();
    }
}
