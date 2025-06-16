// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {MerkleRootPoster} from "@/MerkleRootPoster.sol";

contract MerkleRootPosterDeployScript is Script {
    function run() external {
        vm.startBroadcast();
        MerkleRootPoster poster = new MerkleRootPoster();
        vm.stopBroadcast();
    }
}
