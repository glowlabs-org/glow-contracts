// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GuardedCommit} from "@/GuardedCommit.sol";

contract DeployBatchCommit is Script {
    /*address public constant GCC = address(0x21C46173591f39AfC1d2B634b74c98F0576A272B);
    address public constant USDG = address(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);*/

    function run() public {
        vm.startBroadcast();
        GuardedCommit commit = new GuardedCommit();
        vm.stopBroadcast();
    }
}
