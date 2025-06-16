// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GuardedCommit} from "@/GuardedCommit.sol";

contract DeployGuardedCommit is Script {
    function run() public {
        vm.startBroadcast();
        GuardedCommit commit = new GuardedCommit();
        commit.setAuth(address(0x0BD5344f40744F54331d209629eB6800832F7471), true);
        vm.stopBroadcast();
    }
}
