// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TimelockedWallet} from "../src/TimelockedWallet.sol";
import "../src/GCC.sol";
import "forge-std/console.sol";
import {TestArr} from "../src/TestArr.sol";
import "@solady/utils/LibSort.sol";
contract TokenTest is Test {
        TestArr t;

    function setUp() public {
        uint count = 10_000;
        t = new TestArr();
        for(uint i; i<count;++i){
            t.addElement(count-i);
        }
        return;
    }

    function testArraySort() public {
        uint256[] memory arr = t.getArr();
        LibSort.sort(arr);
        
        return;
    }
}
