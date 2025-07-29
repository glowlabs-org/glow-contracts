// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

interface Exchange {
    function exchange(uint256 amount) external;
}

contract Debug2 is Test {
    string goerliForkUrl = vm.envString("MAINNET_RPC");
    uint256 goerliFork;
    address me = 0xD509A9480559337e924C764071009D60aaCA623d;
    address minerPoolGoerli = 0xa2126e06AF1C75686BCBAbb4cD426bE35aEECC0C;

    function setUp() public {
        goerliFork = vm.createFork(goerliForkUrl);
        vm.selectFork(goerliFork);
    }

    function test_goerliClaimBucket_debug() public {
        Exchange usdcRedemption = Exchange(0x1c2cA537757e1823400F857EdBe72B55bbAe0F08);
        address from = 0x9aCf8D0315094d33Aa6875B673EB126483C3A2c0;
        uint256 codeLength = from.code.length;
        bytes memory code = from.code;
        console.logBytes(code);
        address delegated;
        assembly {
            delegated := mload(add(code, 23)) // 23 = offset to the last 20 bytes
        }

        // address delegate = abi.decode(code, (address));
        console2.logAddress(delegated);
        console2.log("codeLength: ", codeLength);
        uint256 amount = 6080;
        // vm.startPrank(from);
        // usdcRedemption.exchange(amount);
        // vm.stopPrank();
    }
}
