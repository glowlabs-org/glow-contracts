// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/temp/MatrixPayout.sol";
import "forge-std/console.sol";

contract TokenTest is Test {
    uint256 constant ONE_WEEK = 1 weeks;
    address simon = address(1);
    address david = address(2);
    MatrixPayout t;
    
    function increaseTimeByWeeks(uint numWeeks) internal  {
        vm.warp(block.timestamp + numWeeks * ONE_WEEK);
    }
    function setUp() public {
        t = new MatrixPayout();
    }

    function testPayoutMatrix() public {
        //  t.
            t.removeGCAZero();
            console.log("total shares = %s", t.totalShares());
        }


        
    }


