// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {BatchCommit} from "@glow/BatchCommit.sol";

contract DeployBatchRetire is Script {
    function run() external {
        address gcc = address(0x960a1C48E5e9415367002C0CC3199C4e9108a520);
        address usdc = address(0xA8875408E0637c2DEAf7F365448AfB7E5539f9eC);
        vm.startBroadcast();
        BatchCommit batchCommit = new BatchCommit(gcc, usdc);
        vm.stopBroadcast();
    }
}
