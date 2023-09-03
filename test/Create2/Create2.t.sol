// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Create2Helper} from "@/helpers/Create2Helper.sol";
import "forge-std/console.sol";

contract Create2Test is Test {
    
    Create2Helper deployer;

    //Precompute


    function setUp() public {
        deployer = new Create2Helper();
    }

    function test_Return() public {
        return;
    }
}
