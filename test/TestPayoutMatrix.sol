// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/temp/MatrixPayout.sol";
import "forge-std/console.sol";
import {Strings} from  "@openzeppelin/contracts/utils/Strings.sol";

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

    function print5x5Matrix() public {
        string memory s;
        uint[5][5] memory payoutMatrix = t.getPayoutMatrix();
        for(uint i; i<5;++i) {
            for(uint j; j<5;++j) {
                s = string(abi.encodePacked(s, " ", Strings.toString(payoutMatrix[i][j])));
            }
            console.log(s);
            s = "";
        }
    }
    function testPayoutMatrix() public {
        //  t.
            print5x5Matrix();
            t.removeGCAZero();
            console.log("total shares = %s", t.totalShares());
            print5x5Matrix();
            console.log("payout for 0", t.findTotalSharesOfGCA(0));
            console.log("payout for 1", t.findTotalSharesOfGCA(1));
            console.log("payout for 2", t.findTotalSharesOfGCA(2));
            console.log("payout for 3", t.findTotalSharesOfGCA(3));
            console.log("payout for 4", t.findTotalSharesOfGCA(4));

        }


        
    }


