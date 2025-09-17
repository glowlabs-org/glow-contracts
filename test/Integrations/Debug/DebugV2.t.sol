// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

interface Exchange {
    function exchange(uint256 amount) external;
}

contract DebugV2 is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    address me = 0xD509A9480559337e924C764071009D60aaCA623d;
    address minerPoolmainnet = 0xa2126e06AF1C75686BCBAbb4cD426bE35aEECC0C;

    function setUp() public {
        mainnetFork = vm.createFork(mainnetForkUrl);
        vm.selectFork(mainnetFork);
    }

    function test_v2_mainnet_claim() public {}
}
